import logging

from sqlalchemy.orm import Session

from app import models
from app.services.fcm import enviar_alerta_push
from app.services.procesos import color_efectivo, es_core, estado_efectivo

logger = logging.getLogger(__name__)

COLORES_ALERTABLES = {"red", "orange"}
TECNOLOGIAS_PROCESO_VALIDAS = {"AIRFLOW", "DATASTAGE", "PENTAHO"}
TECNOLOGIAS_TABLA_VALIDAS = {"QA_CONTROL", "PG_PROD"}
ESTADOS_TABLA_NORMALIZADOS = {
    "ERROR": "ERROR",
    "VACIA": "VACIA",
    "VACÍA": "VACIA",
}


def _formatear_duracion(inicio, fin) -> str:
    segundos = max(0, int((fin - inicio).total_seconds()))
    horas, resto = divmod(segundos, 3600)
    minutos = resto // 60
    if horas:
        return f"{horas}h {minutos}m"
    return f"{minutos}m"


def _episodio_abierto(db: Session, nombre: str, tecnologia: str):
    """Episodio abierto = misma fila hasta que se cierre con Estado_Fin='OK',
    sin importar si cruza medianoche - un incidente real dura lo que dure."""

    return (
        db.query(models.BitacoraError)
        .filter(
            models.BitacoraError.nombre == nombre,
            models.BitacoraError.tecnologia == tecnologia,
            models.BitacoraError.estado_fin == "ERROR",
        )
        .order_by(models.BitacoraError.id.desc())
        .first()
    )


def _actualizar_bitacora_proceso(db: Session, proceso: models.Control) -> None:
    """Un episodio de error = una fila mientras el proceso siga sin volver a
    verde (se relee cada 5 min), sin cortar por dia calendario. Si el color de
    origen no es ninguno de los conocidos (red/orange/green), se registra
    igual como ADVERTENCIA en vez de perderse en silencio."""

    color = color_efectivo(proceso)
    conocido = color in ("red", "green")
    episodio_abierto = _episodio_abierto(db, proceso.nombre, proceso.fuente)

    if not conocido:
        if episodio_abierto:
            episodio_abierto.fecha_actualizacion = proceso.snapshot_ts
        else:
            db.add(
                models.BitacoraError(
                    fecha_hora=proceso.snapshot_ts,
                    fecha_actualizacion=proceso.snapshot_ts,
                    nombre=proceso.nombre,
                    tecnologia=proceso.fuente,
                    estado="ADVERTENCIA",
                    estado_fin="ERROR",
                    tipo="PROCESO",
                    descripcion=(
                        f"Proceso presentó ADVERTENCIA a las {proceso.snapshot_ts.strftime('%H:%M')} "
                        f"(estado original: {proceso.estado}, color: {proceso.color})."
                    ),
                )
            )
        return

    if color == "red":
        estado_actual = estado_efectivo(proceso)
        if episodio_abierto:
            episodio_abierto.fecha_actualizacion = proceso.snapshot_ts
        else:
            db.add(
                models.BitacoraError(
                    fecha_hora=proceso.snapshot_ts,
                    fecha_actualizacion=proceso.snapshot_ts,
                    nombre=proceso.nombre,
                    tecnologia=proceso.fuente,
                    estado=estado_actual,
                    estado_fin="ERROR",
                    tipo="PROCESO",
                    descripcion=f"Proceso presentó {estado_actual} a las {proceso.snapshot_ts.strftime('%H:%M')}.",
                )
            )
    elif episodio_abierto:
        episodio_abierto.fecha_actualizacion = proceso.snapshot_ts
        episodio_abierto.estado_fin = "OK"
        duracion = _formatear_duracion(episodio_abierto.fecha_hora, proceso.snapshot_ts)
        episodio_abierto.descripcion += (
            f" Se recuperó a las {proceso.snapshot_ts.strftime('%H:%M')}. Duración: {duracion}."
        )


def _actualizar_bitacora_tabla(db: Session, tabla: models.Tabla) -> None:
    """Misma logica de episodio que _actualizar_bitacora_proceso, mirando
    dataops_catalogo_tablas en vez de dataops_catalogo_procesos."""

    conocido = tabla.color in ("red", "green")
    episodio_abierto = _episodio_abierto(db, tabla.nombre, tabla.fuente)

    if not conocido:
        if episodio_abierto:
            episodio_abierto.fecha_actualizacion = tabla.snapshot_ts
        else:
            db.add(
                models.BitacoraError(
                    fecha_hora=tabla.snapshot_ts,
                    fecha_actualizacion=tabla.snapshot_ts,
                    nombre=tabla.nombre,
                    tecnologia=tabla.fuente,
                    estado="ADVERTENCIA",
                    estado_fin="ERROR",
                    tipo="TABLA",
                    descripcion=(
                        f"Tabla presentó ADVERTENCIA a las {tabla.snapshot_ts.strftime('%H:%M')} "
                        f"(estado original: {tabla.estado}, color: {tabla.color})."
                    ),
                )
            )
        return

    if tabla.color == "red":
        estado_normalizado = ESTADOS_TABLA_NORMALIZADOS.get(tabla.estado.upper().strip(), "ERROR")
        if episodio_abierto:
            episodio_abierto.fecha_actualizacion = tabla.snapshot_ts
        else:
            db.add(
                models.BitacoraError(
                    fecha_hora=tabla.snapshot_ts,
                    fecha_actualizacion=tabla.snapshot_ts,
                    nombre=tabla.nombre,
                    tecnologia=tabla.fuente,
                    estado=estado_normalizado,
                    estado_fin="ERROR",
                    tipo="TABLA",
                    descripcion=(
                        f"Tabla presentó {estado_normalizado} a las {tabla.snapshot_ts.strftime('%H:%M')} "
                        f"(cantidad={tabla.cantidad})."
                    ),
                )
            )
    elif episodio_abierto:
        episodio_abierto.fecha_actualizacion = tabla.snapshot_ts
        episodio_abierto.estado_fin = "OK"
        duracion = _formatear_duracion(episodio_abierto.fecha_hora, tabla.snapshot_ts)
        episodio_abierto.descripcion += (
            f" Se recuperó a las {tabla.snapshot_ts.strftime('%H:%M')}. Duración: {duracion}."
        )


def _tablas_de_proceso(db: Session, proceso_nombre: str) -> list[str]:
    filas = (
        db.query(models.ProcesoTabla.tabla_nombre)
        .filter(
            models.ProcesoTabla.proceso_nombre == proceso_nombre,
            models.ProcesoTabla.activo.is_(True),
            models.ProcesoTabla.tipo_relacion == "ALIMENTA",
        )
        .all()
    )
    return [fila[0] for fila in filas]


def _procesos_que_alimentan(db: Session, tabla_nombre: str) -> list[str]:
    filas = (
        db.query(models.ProcesoTabla.proceso_nombre)
        .filter(
            models.ProcesoTabla.tabla_nombre == tabla_nombre,
            models.ProcesoTabla.activo.is_(True),
            models.ProcesoTabla.tipo_relacion == "ALIMENTA",
        )
        .all()
    )
    return [fila[0] for fila in filas]


def _obtener_destinatarios(db: Session):
    return (
        db.query(models.Usuario, models.UsuarioFcmToken)
        .join(models.UsuarioFcmToken, models.UsuarioFcmToken.usuario_id == models.Usuario.id)
        .filter(models.Usuario.activo.is_(True))
        .all()
    )


def _alertar_a_destinatarios(db: Session, control_id: int, mensaje: str, titulo: str) -> None:
    for usuario, token_row in _obtener_destinatarios(db):
        alerta = models.Alerta(
            control_id=control_id,
            usuario_id=usuario.id,
            mensaje=mensaje,
            nivel="critica",
        )
        db.add(alerta)
        try:
            enviar_alerta_push(token_row.fcm_token, titulo=titulo, cuerpo=mensaje, critica=True)
            alerta.enviada = True
        except Exception:
            logger.exception("Fallo al enviar push a usuario %s (control %s)", usuario.id, control_id)
            alerta.enviada = False


def _registrar_incoherencia(
    db: Session,
    proceso_id: int,
    proceso_nombre: str,
    proceso_fuente: str,
    tabla_nombre: str,
    tabla_estado: str,
    ts,
) -> None:
    """Un proceso core que termino OK pero cuya tabla dependiente quedo vacia/en
    error: el proceso no lo reporta como error (por eso el monitor normal no lo
    alcanza a ver), asi que se registra aparte como 'fallo silencioso' y se
    alerta igual que una falla critica normal. Mismo criterio de episodio
    abierto (estado_fin='ERROR', sin corte por dia) que el resto de la
    bitacora."""

    nombre_compuesto = f"{proceso_nombre} -> {tabla_nombre}"
    ya_registrada = _episodio_abierto(db, nombre_compuesto, proceso_fuente)
    if ya_registrada:
        ya_registrada.fecha_actualizacion = ts
        return

    mensaje = (
        f"Proceso {proceso_nombre} presentó INCOHERENCIA a las {ts.strftime('%H:%M')}: "
        f"finalizó OK pero la tabla {tabla_nombre} quedó en estado {tabla_estado} "
        f"(posible fallo silencioso)."
    )
    db.add(
        models.BitacoraError(
            fecha_hora=ts,
            fecha_actualizacion=ts,
            nombre=nombre_compuesto,
            tecnologia=proceso_fuente,
            estado="INCOHERENCIA",
            estado_fin="ERROR",
            tipo="PROCESO",
            descripcion=mensaje,
        )
    )
    _alertar_a_destinatarios(db, proceso_id, mensaje, titulo="Fallo silencioso detectado")


def _cerrar_incoherencia_si_existe(
    db: Session, proceso_nombre: str, proceso_fuente: str, tabla_nombre: str, ts
) -> None:
    """`_registrar_incoherencia` nunca se llamaba de vuelta cuando la
    incoherencia se resolvia, asi que el episodio quedaba "abierto" para
    siempre en la bitacora aunque la tabla ya estuviera bien. Se cierra aca,
    con el mismo criterio de episodio que el resto de la bitacora."""

    nombre_compuesto = f"{proceso_nombre} -> {tabla_nombre}"
    abierta = _episodio_abierto(db, nombre_compuesto, proceso_fuente)
    if abierta is None:
        return
    abierta.fecha_actualizacion = ts
    abierta.estado_fin = "OK"
    duracion = _formatear_duracion(abierta.fecha_hora, ts)
    abierta.descripcion += f" Se recuperó a las {ts.strftime('%H:%M')}. Duración: {duracion}."


def _revisar_incoherencia_desde_proceso(db: Session, proceso: models.Control) -> None:
    for tabla_nombre in _tablas_de_proceso(db, proceso.nombre):
        tabla = (
            db.query(models.Tabla)
            .filter(
                models.Tabla.nombre == tabla_nombre,
                models.Tabla.snapshot_fecha == proceso.snapshot_fecha,
            )
            .order_by(models.Tabla.id.desc())
            .first()
        )
        if tabla and tabla.color == "red":
            _registrar_incoherencia(
                db, proceso.id, proceso.nombre, proceso.fuente, tabla.nombre, tabla.estado,
                proceso.snapshot_ts,
            )
        else:
            _cerrar_incoherencia_si_existe(
                db, proceso.nombre, proceso.fuente, tabla_nombre, proceso.snapshot_ts
            )


def _revisar_incoherencia_desde_tabla(db: Session, tabla: models.Tabla) -> None:
    for proceso_nombre in _procesos_que_alimentan(db, tabla.nombre):
        proceso = (
            db.query(models.Control)
            .filter(
                models.Control.nombre == proceso_nombre,
                models.Control.snapshot_fecha == tabla.snapshot_fecha,
            )
            .order_by(models.Control.id.desc())
            .first()
        )
        if proceso and color_efectivo(proceso) == "green" and es_core(proceso):
            _registrar_incoherencia(
                db, proceso.id, proceso.nombre, proceso.fuente, tabla.nombre, tabla.estado,
                tabla.snapshot_ts,
            )
        elif proceso:
            _cerrar_incoherencia_si_existe(
                db, proceso_nombre, proceso.fuente, tabla.nombre, tabla.snapshot_ts
            )


def _obtener_o_crear_estado(db: Session) -> models.PollerState:
    estado = db.query(models.PollerState).first()
    if estado is None:
        ultimo_id = db.query(models.Control.id).order_by(models.Control.id.desc()).limit(1).scalar() or 0
        estado = models.PollerState(ultimo_id_revisado=ultimo_id)
        db.add(estado)
        db.commit()
        db.refresh(estado)
    return estado


def revisar_procesos_nuevos(db: Session) -> int:
    """Busca snapshots nuevos en dataops_catalogo_procesos (id mayor al ultimo revisado)
    y genera una alerta + push por cada proceso en rojo/naranja. Devuelve cuantos
    procesos nuevos generaron alerta."""

    estado_poller = _obtener_o_crear_estado(db)

    nuevos = (
        db.query(models.Control)
        .filter(models.Control.id > estado_poller.ultimo_id_revisado)
        .order_by(models.Control.id.asc())
        .all()
    )
    if not nuevos:
        return 0

    destinatarios = _obtener_destinatarios(db)
    procesos_alertados = 0

    for proceso in nuevos:
        color = color_efectivo(proceso)

        if proceso.fuente in TECNOLOGIAS_PROCESO_VALIDAS:
            _actualizar_bitacora_proceso(db, proceso)

        if color == "green" and es_core(proceso):
            _revisar_incoherencia_desde_proceso(db, proceso)

        if color in COLORES_ALERTABLES:
            es_critica = color == "red"
            mensaje = f"[{proceso.fuente}] {proceso.nombre}: {estado_efectivo(proceso)}"

            for usuario, token_row in destinatarios:
                alerta = models.Alerta(
                    control_id=proceso.id,
                    usuario_id=usuario.id,
                    mensaje=mensaje,
                    nivel="critica" if es_critica else "normal",
                )
                db.add(alerta)

                try:
                    enviar_alerta_push(
                        token_row.fcm_token,
                        titulo="Alerta de proceso" if es_critica else "Proceso demorado",
                        cuerpo=mensaje,
                        critica=es_critica,
                    )
                    alerta.enviada = True
                except Exception:
                    logger.exception(
                        "Fallo al enviar push a usuario %s (proceso %s)", usuario.id, proceso.id
                    )
                    alerta.enviada = False

            procesos_alertados += 1

    estado_poller.ultimo_id_revisado = nuevos[-1].id
    db.commit()
    return procesos_alertados


def revisar_tablas_nuevas(db: Session) -> int:
    """Busca snapshots nuevos en dataops_catalogo_tablas (id mayor al ultimo revisado)
    y actualiza la bitacora con la misma logica de episodio que los procesos.
    No genera alertas push, solo llena la bitacora."""

    estado_poller = _obtener_o_crear_estado(db)

    nuevas = (
        db.query(models.Tabla)
        .filter(models.Tabla.id > estado_poller.ultimo_id_tablas_revisado)
        .order_by(models.Tabla.id.asc())
        .all()
    )
    if not nuevas:
        return 0

    for tabla in nuevas:
        if tabla.fuente in TECNOLOGIAS_TABLA_VALIDAS:
            _actualizar_bitacora_tabla(db, tabla)

        if tabla.color == "red":
            _revisar_incoherencia_desde_tabla(db, tabla)

    estado_poller.ultimo_id_tablas_revisado = nuevas[-1].id
    db.commit()
    return len(nuevas)
