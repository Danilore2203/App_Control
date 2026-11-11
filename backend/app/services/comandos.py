"""Cola de comandos app -> OP_PROD.

El servidor OP vive en la red interna de Nuevatel y Render no puede entrar;
lo unico que sale de esa red es HTTPS. Entonces la app no le habla a OP:
deja un comando aca (POST /comandos), OP_PROD lo retira cada pocos segundos
(GET /internal/comandos/pendientes), lo ejecuta con sus propias funciones
(sesiones, lanzar proceso, pausar DAG, actualizar todos...) y devuelve el
resultado (POST /internal/comandos/{id}/resultado). La app consulta
GET /comandos/{id} hasta verlo terminado. Mismo esquema que el bot de
Telegram, que tambien opera desde adentro.

Las consultas (ver sesiones) las puede pedir cualquier usuario; las
acciones (cancelar, lanzar, pausar, actualizar) solo administradores.
"""
import json
from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app import auth, models, schemas

# tipo -> requiere admin. OP_PROD responde con error los tipos que no conoce.
TIPOS_COMANDO: dict[str, bool] = {
    # Infraestructura
    "infra.netezza.sesiones": False,
    "infra.netezza.abort_txn": True,  # payload: {"session_id": int}
    "infra.netezza.kill": True,  # payload: {"session_id": int}; DROP SESSION
    "infra.netezza.bloqueos": False,  # quien frena a quien, transacciones abiertas y consultas trabadas
    "infra.postgres.sesiones": False,  # payload: {"entorno": "dev"|"prod", "solo_activas": bool}
    "infra.postgres.cancel": True,  # payload: {"entorno": "dev"|"prod", "pid": int}
    # Procesos
    "procesos.lanzar": True,  # payload: {"nombre": str, "fuente": str}; devuelve lanzado_en
    "procesos.lanzar.estado": False,  # payload: {"nombre": str, "lanzado_en": str}: sigue la corrida lanzada
    "procesos.actualizar_todos": True,
    "procesos.actualizar_todos.estado": False,
    "tablas.actualizar_todos": True,
    "tablas.actualizar_todos.estado": False,
    "tablas.serie": False,  # payload: {"tabla": str}; filas cargadas por dia (ultimos 40), la grafica de la web
    # Airflow
    "airflow.trigger": True,  # payload: {"dag_id": str}
    "airflow.pausar": True,  # payload: {"dag_id": str, "pausar": bool}
    # RA (archivos FTP -> MySQL, el «Actualizar» del Monitor RA de la web)
    "ra.resumen": True,  # devuelve filas del monitor RA + contadores por estado (solo administradores)
    "ra.actualizar_todos": True,  # sincroniza todas las configuraciones FTP activas y devuelve el resumen
    "ra.detalle": True,  # payload: {"archivo": str}; ruta FTP, de que procesos depende y quien lo usa
    # Reportes (Monitor FTP de la web: Excel que se abren en el servidor 208). Todo solo administradores.
    "reportes.resumen": True,  # reportes con su estado, contadores y la cola del 208
    "reportes.lanzar": True,  # payload: {"archivo": str}; abre el libro en el 208 (respeta el maximo abiertos)
    "reportes.lanzar.estado": True,  # payload: {"job_id": str}; como va esa apertura
    "reportes.cola.candidatos": True,  # que entraria a la cola y que no
    "reportes.cola.iniciar": True,  # «Iniciar cola»: abre los elegibles, cada uno a su hora
    "reportes.cola.estado": True,
    "reportes.cola.detener": True,  # «Cancelar pendientes»
}

# Si OP_PROD no lo retiro en este tiempo esta caido o sin red: la app no
# tiene que quedarse esperando para siempre.
EXPIRA_PENDIENTE_SEGUNDOS = 120
# Y si lo retiro pero nunca contesto (se reinicio en el medio).
EXPIRA_EN_CURSO_SEGUNDOS = 3 * 3600  # un job DataStage puede tardar mucho; OP_PROD responde al terminar
# Lo que puede esperar mas en la cola: nadie esta mirando la pantalla, y si
# OP_PROD vuelve dentro de ese tiempo (reinicio, corte de red) igual sale.
EXPIRA_PENDIENTE_POR_TIPO: dict[str, int] = {
    "correo.recuperar_password": 15 * 60,  # lo que vale el codigo
}
# Veces que un comando vuelve a la cola porque una copia de OP_PROD no lo conocia.
MAX_RECHAZOS = 5
# OP_PROD consulta cada ~3 s: si no aparece en este tiempo, nadie atiende.
OP_CAIDO_SIN_LATIDO_SEGUNDOS = 90
LATIDO_CADA_SEGUNDOS = 20


# Comandos que crea el propio backend (la app no los puede pedir: no estan en
# TIPOS_COMANDO) y cuyo payload lleva datos que solo OP_PROD debe ver. El
# codigo de recuperacion viaja para que OP lo mande por correo, pero en
# cualquier otra salida va tapado y se borra del registro al terminar.
CAMPOS_RESERVADOS: dict[str, tuple[str, ...]] = {
    "correo.recuperar_password": ("codigo",),
}


def _payload(c: models.Comando, completo: bool = False) -> dict:
    datos = json.loads(c.payload or "{}")
    if not completo and isinstance(datos, dict):
        for campo in CAMPOS_RESERVADOS.get(c.tipo, ()):
            if campo in datos:
                datos[campo] = "***"
    return datos


def _borrar_reservados(c: models.Comando) -> None:
    if c.tipo in CAMPOS_RESERVADOS:
        c.payload = json.dumps(_payload(c), ensure_ascii=False)


def _a_salida(c: models.Comando, completo: bool = False) -> schemas.ComandoOut:
    """`completo` solo para OP_PROD (tomar_pendientes): es el unico que
    necesita los campos reservados para ejecutar el comando."""
    return schemas.ComandoOut(
        id=c.id,
        tipo=c.tipo,
        payload=_payload(c, completo),
        estado=c.estado,
        creado_en=c.creado_en,
        tomado_en=c.tomado_en,
        terminado_en=c.terminado_en,
        resultado=json.loads(c.resultado) if c.resultado else None,
        error=c.error,
        creado_por=(c.creado_por.nombre or c.creado_por.username) if c.creado_por else None,
    )


def crear_comando(db: Session, usuario: models.Usuario, pedido: schemas.ComandoIn) -> schemas.ComandoOut:
    if pedido.tipo not in TIPOS_COMANDO:
        raise HTTPException(status_code=400, detail=f"Comando desconocido: {pedido.tipo}")
    if TIPOS_COMANDO[pedido.tipo] and not auth.es_administrador(usuario, db):
        raise HTTPException(status_code=403, detail="Esta accion requiere permisos de administrador")
    comando = models.Comando(
        tipo=pedido.tipo,
        payload=json.dumps(pedido.payload, ensure_ascii=False),
        estado="pendiente",
        creado_por_id=usuario.id,
        creado_en=datetime.utcnow(),
    )
    db.add(comando)
    db.commit()
    db.refresh(comando)
    return _a_salida(comando)


def obtener_comando(db: Session, comando_id: int, usuario: models.Usuario) -> schemas.ComandoOut:
    comando = db.get(models.Comando, comando_id)
    if comando is None:
        raise HTTPException(status_code=404, detail="Comando no encontrado")
    if comando.creado_por_id != usuario.id and not auth.es_administrador(usuario, db):
        raise HTTPException(status_code=403, detail="No es tu comando")
    expirar_vencidos(db)
    db.refresh(comando)
    return _a_salida(comando)


def listar_recientes(db: Session, limite: int = 50) -> list[schemas.ComandoOut]:
    filas = db.query(models.Comando).order_by(models.Comando.creado_en.desc()).limit(limite).all()
    return [_a_salida(c) for c in filas]


def expirar_vencidos(db: Session, ahora: Optional[datetime] = None) -> int:
    ahora = ahora or datetime.utcnow()
    especiales = list(EXPIRA_PENDIENTE_POR_TIPO)
    pendiente_vencido = (
        (models.Comando.estado == "pendiente")
        & models.Comando.tipo.notin_(especiales)
        & (models.Comando.creado_en < ahora - timedelta(seconds=EXPIRA_PENDIENTE_SEGUNDOS))
    )
    for tipo, segundos in EXPIRA_PENDIENTE_POR_TIPO.items():
        pendiente_vencido = pendiente_vencido | (
            (models.Comando.estado == "pendiente")
            & (models.Comando.tipo == tipo)
            & (models.Comando.creado_en < ahora - timedelta(seconds=segundos))
        )
    en_curso_vencido = (models.Comando.estado == "en_curso") & (
        models.Comando.tomado_en < ahora - timedelta(seconds=EXPIRA_EN_CURSO_SEGUNDOS)
    )
    vencidos = db.query(models.Comando).filter(pendiente_vencido | en_curso_vencido).all()
    for c in vencidos:
        c.estado = "expirado"
        c.terminado_en = ahora
        c.error = "OP_PROD no respondio a tiempo (sin conexion o apagado)"
        _borrar_reservados(c)
    if vencidos:
        db.commit()
    return len(vencidos)


def _anotar_latido(db: Session, tipos: Optional[set[str]], ahora: datetime) -> None:
    """Deja constancia de que OP_PROD esta atendiendo (y que sabe hacer). Se
    escribe como mucho cada LATIDO_CADA_SEGUNDOS: OP consulta cada pocos."""
    if tipos is None:
        return
    fila = db.get(models.LatidoOp, "comandos")
    texto = ",".join(sorted(tipos))
    if fila is None:
        db.add(models.LatidoOp(clave="comandos", visto_en=ahora, tipos=texto))
    elif fila.tipos != texto or fila.visto_en < ahora - timedelta(seconds=LATIDO_CADA_SEGUNDOS):
        fila.visto_en = ahora
        fila.tipos = texto


def op_atiende(db: Session, tipo: str, ahora: Optional[datetime] = None) -> bool:
    """Si hay una copia de OP_PROD retirando comandos y sabe hacer `tipo`."""
    ahora = ahora or datetime.utcnow()
    fila = db.get(models.LatidoOp, "comandos")
    if fila is None:
        # Ningun OP_PROD anuncio todavia lo que sabe hacer (version anterior):
        # no hay como saberlo, se asume que si, como antes.
        return True
    if fila.visto_en < ahora - timedelta(seconds=OP_CAIDO_SIN_LATIDO_SEGUNDOS):
        return False
    return tipo in (fila.tipos or "").split(",")


def _alguien_lo_sabe_hacer(db: Session, tipo: str, ahora: Optional[datetime] = None) -> bool:
    """Hay una copia de OP_PROD atendiendo ahora que anuncio saber hacer `tipo`
    (a diferencia de op_atiende, sin datos es que no)."""
    ahora = ahora or datetime.utcnow()
    fila = db.get(models.LatidoOp, "comandos")
    return (
        fila is not None
        and fila.visto_en >= ahora - timedelta(seconds=OP_CAIDO_SIN_LATIDO_SEGUNDOS)
        and tipo in (fila.tipos or "").split(",")
    )


def tomar_pendientes(db: Session, limite: int = 10, tipos: Optional[set[str]] = None) -> list[schemas.ComandoOut]:
    """Para OP_PROD: devuelve los pendientes mas viejos y los marca en curso,
    asi dos copias de OP_PROD no ejecutan el mismo comando.

    `tipos`: lo que esa copia de OP_PROD dice saber hacer; solo recibe eso.
    Una copia vieja no lo manda: recibe todo menos lo que ya rechazo alguna
    copia por no conocerlo (eso queda para una que lo anuncie)."""
    expirar_vencidos(db)
    consulta = db.query(models.Comando).filter(models.Comando.estado == "pendiente")
    if tipos is not None:
        consulta = consulta.filter(models.Comando.tipo.in_(sorted(tipos)))
    else:
        consulta = consulta.filter((models.Comando.rechazos == 0) | models.Comando.rechazos.is_(None))
    pendientes = consulta.order_by(models.Comando.creado_en).limit(limite).all()
    ahora = datetime.utcnow()
    for c in pendientes:
        c.estado = "en_curso"
        c.tomado_en = ahora
    _anotar_latido(db, tipos, ahora)
    db.commit()
    return [_a_salida(c, completo=True) for c in pendientes]


def registrar_resultado(db: Session, comando_id: int, resultado: schemas.ComandoResultadoIn) -> schemas.ComandoOut:
    comando = db.get(models.Comando, comando_id)
    if comando is None:
        raise HTTPException(status_code=404, detail="Comando no encontrado")
    # «Comando desconocido»: lo retiro una copia de OP_PROD que no lo sabe
    # hacer (vieja, o el .150 sin reiniciar) y no ejecuto nada. Si hay otra
    # copia atendiendo que dice saber hacerlo, vuelve a la cola para ella
    # (ver tomar_pendientes). Si no hay ninguna, falla ya con un mensaje que
    # dice que hacer, en vez de dejar a la app esperando hasta que expire.
    if not resultado.ok and (resultado.error or "").startswith("Comando desconocido"):
        if (comando.rechazos or 0) < MAX_RECHAZOS and _alguien_lo_sabe_hacer(db, comando.tipo):
            comando.rechazos = (comando.rechazos or 0) + 1
            comando.estado = "pendiente"
            comando.tomado_en = None
            db.commit()
            db.refresh(comando)
            return _a_salida(comando)
        resultado = schemas.ComandoResultadoIn(
            ok=False,
            error=(
                "El OP del servidor .150 todavía no tiene esta función (corre una versión anterior): "
                "hay que reiniciarlo para que tome la nueva."
            ),
        )

    comando.estado = "ok" if resultado.ok else "error"
    comando.terminado_en = datetime.utcnow()
    comando.resultado = (
        json.dumps(resultado.resultado, ensure_ascii=False) if resultado.resultado is not None else None
    )
    comando.error = (resultado.error or "")[:2000] or None
    if resultado.ok and comando.tipo == "correo.recuperar_password":
        from app.services import recuperacion

        recuperacion.correo_enviado(db, comando.id, comando.terminado_en)
    _borrar_reservados(comando)
    db.commit()
    db.refresh(comando)
    return _a_salida(comando)
