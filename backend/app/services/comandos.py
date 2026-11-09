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
    "infra.postgres.sesiones": False,  # payload: {"entorno": "dev"|"prod", "solo_activas": bool}
    "infra.postgres.cancel": True,  # payload: {"entorno": "dev"|"prod", "pid": int}
    # Procesos
    "procesos.lanzar": True,  # payload: {"nombre": str, "fuente": str}; devuelve lanzado_en
    "procesos.lanzar.estado": False,  # payload: {"nombre": str, "lanzado_en": str}: sigue la corrida lanzada
    "procesos.actualizar_todos": True,
    "procesos.actualizar_todos.estado": False,
    "tablas.actualizar_todos": True,
    "tablas.actualizar_todos.estado": False,
    # Airflow
    "airflow.trigger": True,  # payload: {"dag_id": str}
    "airflow.pausar": True,  # payload: {"dag_id": str, "pausar": bool}
}

# Si OP_PROD no lo retiro en este tiempo esta caido o sin red: la app no
# tiene que quedarse esperando para siempre.
EXPIRA_PENDIENTE_SEGUNDOS = 120
# Y si lo retiro pero nunca contesto (se reinicio en el medio).
EXPIRA_EN_CURSO_SEGUNDOS = 600


def _a_salida(c: models.Comando) -> schemas.ComandoOut:
    return schemas.ComandoOut(
        id=c.id,
        tipo=c.tipo,
        payload=json.loads(c.payload or "{}"),
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
    pendiente_vencido = (models.Comando.estado == "pendiente") & (
        models.Comando.creado_en < ahora - timedelta(seconds=EXPIRA_PENDIENTE_SEGUNDOS)
    )
    en_curso_vencido = (models.Comando.estado == "en_curso") & (
        models.Comando.tomado_en < ahora - timedelta(seconds=EXPIRA_EN_CURSO_SEGUNDOS)
    )
    vencidos = db.query(models.Comando).filter(pendiente_vencido | en_curso_vencido).all()
    for c in vencidos:
        c.estado = "expirado"
        c.terminado_en = ahora
        c.error = "OP_PROD no respondio a tiempo (sin conexion o apagado)"
    if vencidos:
        db.commit()
    return len(vencidos)


def tomar_pendientes(db: Session, limite: int = 10) -> list[schemas.ComandoOut]:
    """Para OP_PROD: devuelve los pendientes mas viejos y los marca en curso,
    asi dos copias de OP_PROD no ejecutan el mismo comando."""
    expirar_vencidos(db)
    pendientes = (
        db.query(models.Comando)
        .filter(models.Comando.estado == "pendiente")
        .order_by(models.Comando.creado_en)
        .limit(limite)
        .all()
    )
    ahora = datetime.utcnow()
    for c in pendientes:
        c.estado = "en_curso"
        c.tomado_en = ahora
    db.commit()
    return [_a_salida(c) for c in pendientes]


def registrar_resultado(db: Session, comando_id: int, resultado: schemas.ComandoResultadoIn) -> schemas.ComandoOut:
    comando = db.get(models.Comando, comando_id)
    if comando is None:
        raise HTTPException(status_code=404, detail="Comando no encontrado")
    comando.estado = "ok" if resultado.ok else "error"
    comando.terminado_en = datetime.utcnow()
    comando.resultado = (
        json.dumps(resultado.resultado, ensure_ascii=False) if resultado.resultado is not None else None
    )
    comando.error = (resultado.error or "")[:2000] or None
    db.commit()
    db.refresh(comando)
    return _a_salida(comando)
