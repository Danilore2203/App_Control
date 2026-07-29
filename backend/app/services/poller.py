import logging

from firebase_admin import messaging
from sqlalchemy import func
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
                        f"Proceso en estado ADVERTENCIA a las {proceso.snapshot_ts.strftime('%H:%M')} "
                        f"(estado original: {proceso.estado}, color: {proceso.color})."
                    ),
                )
            )
        return

    if color == "red":
        estado_actual = estado_efectivo(proceso)
        frase_estado = "demorado" if estado_actual == "DEMORADO" else f"en {estado_actual.lower()}"
        if episodio_abierto:
            # El proceso puede pasar de ERROR a DEMORADO (o al reves) sin
            # cerrarse el episodio - sin esto el estado quedaba pegado al
            # que tenia quiando se abrio la fila, aunque el origen ya haya
            # cambiado (por eso demorados reales se seguian viendo como error).
            if episodio_abierto.estado != estado_actual:
                episodio_abierto.descripcion += (
                    f" Cambió a {frase_estado} a las {proceso.snapshot_ts.strftime('%H:%M')}."
                )
                episodio_abierto.estado = estado_actual
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
                    descripcion=f"Proceso {frase_estado} a las {proceso.snapshot_ts.strftime('%H:%M')}.",
                )
            )
    elif episodio_abierto:
        episodio_abierto.fecha_actualizacion = proceso.snapshot_ts
        episodio_abierto.estado_fin = "OK"
        duracion = _formatear_duracion(episodio_abierto.fecha_hora, proceso.snapshot_ts)
        episodio_abierto.descripcion += (
            f" Solucionado - Estado OK a las {proceso.snapshot_ts.strftime('%H:%M')}. Duración: {duracion}."
        )


def _actualizar_bitacora_tabla(db: Session, tabla: models.Tabla) -> None:
    """Misma logica de episodio que _actualizar_bitacora_proceso, mirando
    dataops_catalogo_tablas en vez de dataops_catalogo_procesos. El color se
    normaliza (strip + lower) por la misma razon que en procesos.py: el
    origen no siempre lo escribe con la misma capitalizacion."""

    color_tabla = (tabla.color or "").strip().lower()
    conocido = color_tabla in ("red", "green")
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
                        f"Tabla en estado ADVERTENCIA a las {tabla.snapshot_ts.strftime('%H:%M')} "
                        f"(estado original: {tabla.estado}, color: {tabla.color})."
                    ),
                )
            )
        return

    if color_tabla == "red":
        estado_normalizado = ESTADOS_TABLA_NORMALIZADOS.get(tabla.estado.upper().strip(), "ERROR")
        if episodio_abierto:
            if episodio_abierto.estado != estado_normalizado:
                episodio_abierto.descripcion += (
                    f" Cambió a {estado_normalizado.lower()} a las {tabla.snapshot_ts.strftime('%H:%M')}."
                )
                episodio_abierto.estado = estado_normalizado
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
                        f"Tabla en {estado_normalizado.lower()} a las {tabla.snapshot_ts.strftime('%H:%M')} "
                        f"(cantidad={tabla.cantidad})."
                    ),
                )
            )
    elif episodio_abierto:
        episodio_abierto.fecha_actualizacion = tabla.snapshot_ts
        episodio_abierto.estado_fin = "OK"
        duracion = _formatear_duracion(episodio_abierto.fecha_hora, tabla.snapshot_ts)
        episodio_abierto.descripcion += (
            f" Solucionado - Estado OK a las {tabla.snapshot_ts.strftime('%H:%M')}. Duración: {duracion}."
        )


def resincronizar_episodios_abiertos(db: Session) -> int:
    """Los `_actualizar_bitacora_*` de arriba solo corrigen un episodio
    cuando llega una fila NUEVA para ese proceso/tabla (id > cursor del
    poller). Si el origen tarda en generar una fila nueva para ese proceso
    puntual, el episodio se queda con el estado congelado desde que se abrio
    -por eso un proceso que paso de ERROR a DEMORADO podia seguir viendose
    como ERROR indefinidamente. Esto revisa TODOS los episodios abiertos
    contra el ultimo snapshot conocido (sin importar el cursor) y los
    corrige. Se corre en cada ciclo del poller, ademas de (no en vez de) la
    logica normal basada en filas nuevas."""

    abiertos = (
        db.query(models.BitacoraError)
        .filter(models.BitacoraError.estado_fin == "ERROR")
        .all()
    )
    corregidos = 0

    for episodio in abiertos:
        if episodio.tipo == "PROCESO":
            ultimo = (
                db.query(models.Control)
                .filter(
                    models.Control.nombre == episodio.nombre,
                    models.Control.fuente == episodio.tecnologia,
                )
                .order_by(models.Control.id.desc())
                .first()
            )
            if ultimo is None:
                continue
            color = color_efectivo(ultimo)
            if color not in ("red", "green"):
                continue
            if color == "green":
                episodio.estado_fin = "OK"
                episodio.fecha_actualizacion = ultimo.snapshot_ts
                duracion = _formatear_duracion(episodio.fecha_hora, ultimo.snapshot_ts)
                episodio.descripcion += (
                    f" Solucionado - Estado OK a las {ultimo.snapshot_ts.strftime('%H:%M')}. Duración: {duracion}."
                )
                corregidos += 1
                continue
            estado_actual = estado_efectivo(ultimo)
            if episodio.estado != estado_actual:
                frase = "demorado" if estado_actual == "DEMORADO" else f"en {estado_actual.lower()}"
                episodio.descripcion += (
                    f" Cambió a {frase} a las {ultimo.snapshot_ts.strftime('%H:%M')}."
                )
                episodio.estado = estado_actual
                corregidos += 1
            episodio.fecha_actualizacion = ultimo.snapshot_ts

        elif episodio.tipo == "TABLA":
            ultimo = (
                db.query(models.Tabla)
                .filter(
                    models.Tabla.nombre == episodio.nombre,
                    models.Tabla.fuente == episodio.tecnologia,
                )
                .order_by(models.Tabla.id.desc())
                .first()
            )
            if ultimo is None:
                continue
            color_tabla = (ultimo.color or "").strip().lower()
            if color_tabla not in ("red", "green"):
                continue
            if color_tabla == "green":
                episodio.estado_fin = "OK"
                episodio.fecha_actualizacion = ultimo.snapshot_ts
                duracion = _formatear_duracion(episodio.fecha_hora, ultimo.snapshot_ts)
                episodio.descripcion += (
                    f" Solucionado - Estado OK a las {ultimo.snapshot_ts.strftime('%H:%M')}. Duración: {duracion}."
                )
                corregidos += 1
                continue
            estado_normalizado = ESTADOS_TABLA_NORMALIZADOS.get(ultimo.estado.upper().strip(), "ERROR")
            if episodio.estado != estado_normalizado:
                episodio.descripcion += (
                    f" Cambió a {estado_normalizado.lower()} a las {ultimo.snapshot_ts.strftime('%H:%M')}."
                )
                episodio.estado = estado_normalizado
                corregidos += 1
            episodio.fecha_actualizacion = ultimo.snapshot_ts

    if corregidos:
        db.commit()
    return corregidos


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


def _intentar_push(
    db: Session,
    usuario: models.Usuario,
    token_row: models.UsuarioFcmToken,
    control_id: int,
    mensaje: str,
    titulo: str,
    critica: bool,
) -> bool:
    """Registra la Alerta y hace UN intento de push. Si Firebase dice que el
    token ya no esta registrado (app desinstalada/reinstalada, token
    rotado), no tiene sentido reintentar contra el mismo token para
    siempre -se borra aca mismo, y el usuario vuelve a quedar cubierto en
    cuanto la app guarde un token nuevo (`registrarFcmToken` en el login/
    refresh). Cualquier otro error (red, cuota, etc.) se loggea completo
    para diagnosticar, pero se conserva el token para reintentar."""

    alerta = models.Alerta(control_id=control_id, usuario_id=usuario.id, mensaje=mensaje, nivel="critica" if critica else "normal")
    db.add(alerta)
    try:
        enviar_alerta_push(token_row.fcm_token, titulo=titulo, cuerpo=mensaje, critica=critica)
        alerta.enviada = True
        return True
    except messaging.UnregisteredError:
        logger.warning(
            "Token FCM de usuario %s ya no esta registrado en Firebase: se elimina para no reintentar en vano",
            usuario.id,
        )
        alerta.enviada = False
        db.delete(token_row)
        return False
    except Exception:
        logger.exception("Fallo al enviar push a usuario %s (control %s)", usuario.id, control_id)
        alerta.enviada = False
        return False


def _alertar_a_destinatarios(db: Session, control_id: int, mensaje: str, titulo: str) -> None:
    for usuario, token_row in _obtener_destinatarios(db):
        _intentar_push(db, usuario, token_row, control_id, mensaje, titulo, critica=True)


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
        f"Proceso {proceso_nombre} en incoherencia a las {ts.strftime('%H:%M')}: "
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
    abierta.descripcion += f" Solucionado - Estado OK a las {ts.strftime('%H:%M')}. Duración: {duracion}."


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
        if tabla and (tabla.color or "").strip().lower() == "red":
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
    y actualiza bitacora + incoherencia por cada proceso. Ya NO envia alarmas
    aca (ver `revisar_alarmas_activas`): esto solo miraba filas NUEVAS, asi que
    un proceso que ya estaba en ERROR antes de que el origen volviera a
    escribir una fila para el (o antes de que el poller/token FCM existieran)
    se quedaba sin alarma para siempre. La alarma ahora se decide mirando el
    estado ACTUAL de cada proceso en cada ciclo, no las filas nuevas."""

    estado_poller = _obtener_o_crear_estado(db)

    nuevos = (
        db.query(models.Control)
        .filter(models.Control.id > estado_poller.ultimo_id_revisado)
        .order_by(models.Control.id.asc())
        .all()
    )
    if not nuevos:
        return 0

    procesos_procesados = 0

    for proceso in nuevos:
        color = color_efectivo(proceso)

        if proceso.fuente in TECNOLOGIAS_PROCESO_VALIDAS:
            _actualizar_bitacora_proceso(db, proceso)

        if color == "green" and es_core(proceso):
            _revisar_incoherencia_desde_proceso(db, proceso)

        procesos_procesados += 1

    estado_poller.ultimo_id_revisado = nuevos[-1].id
    db.commit()
    return procesos_procesados


def _estado_actual_procesos(db: Session) -> list[models.Control]:
    """Un registro por (nombre, fuente): el de snapshot_ts mas reciente. Misma
    consulta que expone /controles, para que la alarma se decida sobre
    exactamente lo mismo que ve el usuario en la app, no sobre un cursor
    aparte que puede quedar desincronizado."""

    ultimo_por_proceso = (
        db.query(
            models.Control.nombre,
            models.Control.fuente,
            func.max(models.Control.snapshot_ts).label("ultimo_ts"),
        )
        .group_by(models.Control.nombre, models.Control.fuente)
        .subquery()
    )
    return (
        db.query(models.Control)
        .join(
            ultimo_por_proceso,
            (models.Control.nombre == ultimo_por_proceso.c.nombre)
            & (models.Control.fuente == ultimo_por_proceso.c.fuente)
            & (models.Control.snapshot_ts == ultimo_por_proceso.c.ultimo_ts),
        )
        .all()
    )


def _obtener_episodio_alerta(db: Session, nombre: str, fuente: str) -> models.EpisodioAlerta | None:
    return (
        db.query(models.EpisodioAlerta)
        .filter(models.EpisodioAlerta.nombre == nombre, models.EpisodioAlerta.fuente == fuente)
        .first()
    )


def _disparar_alarma(db: Session, proceso: models.Control, episodio: models.EpisodioAlerta) -> bool:
    """Envia el push a todos los destinatarios y devuelve True si al menos
    uno lo recibio (con eso alcanza para marcar el episodio como avisado;
    si TODOS fallan, se reintenta el proximo ciclo)."""

    color = color_efectivo(proceso)
    es_critica = color == "red"
    mensaje = f"[{proceso.fuente}] {proceso.nombre}: {estado_efectivo(proceso)}"
    titulo = (
        "Alerta de proceso CORE" if es_core(proceso) and es_critica
        else "Alerta de proceso" if es_critica
        else "Proceso demorado"
    )

    destinatarios = _obtener_destinatarios(db)
    if not destinatarios:
        logger.warning(
            "No hay destinatarios con token FCM registrado: no se puede alarmar %s [%s]",
            proceso.nombre, proceso.fuente,
        )
        return False

    logger.warning(
        "Disparando alarma para %s [%s] (core=%s, color=%s) a %d destinatario(s)",
        proceso.nombre, proceso.fuente, es_core(proceso), color, len(destinatarios),
    )

    algun_envio_ok = False
    for usuario, token_row in destinatarios:
        if _intentar_push(db, usuario, token_row, proceso.id, mensaje, titulo, critica=es_critica):
            algun_envio_ok = True

    return algun_envio_ok


def _revisar_alarma_de_proceso(db: Session, proceso: models.Control) -> bool:
    """Decide si hace falta (re)disparar la alarma para el estado ACTUAL de
    este proceso, sin importar si esta fila es nueva o ya se habia visto
    antes. Devuelve True si se disparo (o reintento) un push exitoso."""

    color = color_efectivo(proceso)
    episodio = _obtener_episodio_alerta(db, proceso.nombre, proceso.fuente)

    if color not in COLORES_ALERTABLES:
        if episodio is not None and episodio.abierto:
            episodio.abierto = False
            episodio.cerrado_en = proceso.snapshot_ts
            logger.info("Alarma cerrada: %s [%s] volvio a %s", proceso.nombre, proceso.fuente, color)
        return False

    episodio_nuevo = episodio is None
    reabre = episodio is not None and not episodio.abierto
    reintento_pendiente = episodio is not None and episodio.abierto and not episodio.push_ok

    if episodio_nuevo:
        episodio = models.EpisodioAlerta(
            nombre=proceso.nombre,
            fuente=proceso.fuente,
            color=color,
            abierto=True,
            control_id_actual=proceso.id,
            primera_deteccion=proceso.snapshot_ts,
        )
        db.add(episodio)
        logger.warning("Nueva alarma detectada: %s [%s] en %s", proceso.nombre, proceso.fuente, estado_efectivo(proceso))
    elif reabre:
        episodio.abierto = True
        episodio.push_ok = False
        episodio.primera_deteccion = proceso.snapshot_ts
        episodio.cerrado_en = None
        logger.warning("Proceso %s [%s] volvio a fallar: reabre alarma", proceso.nombre, proceso.fuente)
    elif reintento_pendiente:
        logger.info("Reintentando alarma pendiente: %s [%s]", proceso.nombre, proceso.fuente)

    episodio.color = color
    episodio.control_id_actual = proceso.id

    if not (episodio_nuevo or reabre or reintento_pendiente):
        # Ya hay alarma activa y avisada para este episodio: no duplicar.
        return False

    exito = _disparar_alarma(db, proceso, episodio)
    episodio.push_ok = exito
    episodio.ultima_alerta_en = proceso.snapshot_ts
    return exito


def revisar_alarmas_activas(db: Session) -> int:
    """Recorre el estado ACTUAL de todos los procesos (no solo filas nuevas)
    y garantiza que exista una alarma activa mientras alguno siga en
    rojo/naranja. Corrige el bug de fondo: antes la alarma solo se evaluaba
    cuando llegaba una fila nueva del origen, asi que un proceso que YA
    estaba en ERROR (sin fila nueva todavia, o detectado antes de que
    hubiera un token FCM registrado) nunca generaba push. Se commitea
    proceso por proceso para que una falla puntual en uno no le cueste la
    alarma a los demas."""

    disparadas = 0
    for proceso in _estado_actual_procesos(db):
        try:
            if _revisar_alarma_de_proceso(db, proceso):
                disparadas += 1
            db.commit()
        except Exception:
            db.rollback()
            logger.exception(
                "Fallo revisando alarma de %s [%s]; se reintenta el proximo ciclo",
                proceso.nombre, proceso.fuente,
            )
    return disparadas


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

        if (tabla.color or "").strip().lower() == "red":
            _revisar_incoherencia_desde_tabla(db, tabla)

    estado_poller.ultimo_id_tablas_revisado = nuevas[-1].id
    db.commit()
    return len(nuevas)
