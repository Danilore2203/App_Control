import logging
from datetime import date, datetime, time, timedelta, timezone
from types import SimpleNamespace

from firebase_admin import messaging
from sqlalchemy import func, inspect, select
from sqlalchemy.orm import Session
from sqlalchemy.orm.exc import ObjectDeletedError

from app import models
from app.services.fcm import enviar_actualizacion_push, enviar_alerta_push, enviar_resumen_push
from app.services.procesos import color_efectivo, es_core, estado_efectivo, recuperado_confirmado

logger = logging.getLogger(__name__)

COLORES_ALERTABLES = {"red", "orange"}
BOLIVIA_TZ = timezone(timedelta(hours=-4))
ESTADOS_TABLA_NORMALIZADOS = {
    "ERROR": "ERROR",
    "VACIA": "VACIA",
    "VACÍA": "VACIA",
}
# Tabla todavia cargando: ni error ni exito, no se registra ni se alerta.
ESTADOS_TABLA_TRANSITORIOS = {"EN PROCESO"}


def hora_cambio(fila) -> datetime:
    """Hora del ultimo cambio de ESTADO de una fila de catalogo. snapshot_ts
    se mueve con cualquier columna (hora_log, cantidad...), asi que para
    "en error desde las HH:MM" la hora correcta es estado_ts. Cae a
    snapshot_ts en filas anteriores a que existiera la columna."""
    return getattr(fila, "estado_ts", None) or fila.snapshot_ts


def _formatear_duracion(inicio, fin) -> str:
    segundos = max(0, int((fin - inicio).total_seconds()))
    horas, resto = divmod(segundos, 3600)
    minutos = resto // 60
    if horas:
        return f"{horas}h {minutos}m"
    return f"{minutos}m"


DESCRIPCION_MAX_LEN = 1000  # debe calzar con BitacoraError.descripcion = String(1000)
_DESCRIPCION_TRUNCADO_PREFIJO = "[...] "


def _agregar_a_descripcion(episodio: "models.BitacoraError", fragmento: str) -> None:
    """Agrega texto a la descripcion de un episodio sin superar el limite de
    la columna (String(1000)): un episodio "flapping" (varios ciclos
    cambiando de estado) puede acumular texto indefinidamente, y un UPDATE
    que excede el limite lo rechaza Postgres, abortando la transaccion
    completa del lote (todos los episodios de ese ciclo, no solo este).
    Si no entra, se recorta el principio y se antepone un marcador -se
    prioriza conservar el historial mas reciente."""

    nueva = (episodio.descripcion or "") + fragmento
    if len(nueva) > DESCRIPCION_MAX_LEN:
        recorte = DESCRIPCION_MAX_LEN - len(_DESCRIPCION_TRUNCADO_PREFIJO)
        nueva = _DESCRIPCION_TRUNCADO_PREFIJO + nueva[-recorte:]
    episodio.descripcion = nueva


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


def resincronizar_episodios_abiertos(db: Session) -> int:
    """Revisa los episodios abiertos PROPIOS de la app (origen_id NULL:
    incoherencias proceso/tabla y entradas manuales) contra el estado actual
    del catalogo y los cierra o corrige. Los episodios de procesos y tablas
    ya no los genera la app: vienen replicados de la bitacora de MySQL
    (origen_id con valor), donde OP_PROD los abre y cierra; tocarlos aca
    seria tener dos escritores con criterios distintos."""

    abiertos = (
        db.query(models.BitacoraError)
        .filter(models.BitacoraError.estado_fin == "ERROR", models.BitacoraError.origen_id.is_(None))
        .all()
    )
    corregidos = 0

    for episodio in abiertos:
        try:
            # Igual que en revisar_procesos_nuevos/revisar_tablas_nuevas: se
            # capturan en variables planas antes de usarlas en el log del
            # except, porque el commit/rollback expira el objeto y volver a
            # tocar episodio.* ahi podria disparar un segundo ObjectDeletedError.
            ep_id, ep_nombre, ep_tecnologia = episodio.id, episodio.nombre, episodio.tecnologia
            if episodio.tipo == "PROCESO":
                ultimo = (
                    db.query(models.Control)
                    .filter(
                        models.Control.nombre == episodio.nombre,
                        models.Control.fuente == episodio.tecnologia,
                    )
                    .order_by(models.Control.snapshot_fecha.desc(), models.Control.snapshot_ts.desc())
                    .first()
                )
                if ultimo is None:
                    continue
                hora = hora_cambio(ultimo)
                color = color_efectivo(ultimo)
                if color != "red":
                    # Ya no esta en rojo -verde, en ejecucion, o cualquier otro
                    # estado-: la falla vieja quedo atras (si vuelve a fallar,
                    # el proximo aviso abre un episodio nuevo). Antes esto solo
                    # cerraba si el color era exactamente "green", asi que un
                    # proceso que arrancaba una corrida nueva y quedaba "en
                    # ejecucion" (azul) dejaba el episodio viejo abierto para
                    # siempre -de ahi que bitacora acumulara episodios "abiertos"
                    # que la app ya no mostraba como fallando.
                    episodio.estado_fin = "OK"
                    episodio.fecha_actualizacion = hora
                    duracion = _formatear_duracion(episodio.fecha_hora, hora)
                    _agregar_a_descripcion(
                        episodio,
                        f" Solucionado - Estado OK a las {hora.strftime('%H:%M')}. Duración: {duracion}.",
                    )
                    corregidos += 1
                else:
                    estado_actual = estado_efectivo(ultimo)
                    if episodio.estado != estado_actual:
                        frase = "demorado" if estado_actual == "DEMORADO" else f"en {estado_actual.lower()}"
                        _agregar_a_descripcion(
                            episodio, f" Cambió a {frase} a las {hora.strftime('%H:%M')}."
                        )
                        episodio.estado = estado_actual
                        corregidos += 1
                    episodio.fecha_actualizacion = hora

            elif episodio.tipo == "TABLA":
                ultimo = (
                    db.query(models.Tabla)
                    .filter(
                        models.Tabla.nombre == episodio.nombre,
                        models.Tabla.fuente == episodio.tecnologia,
                    )
                    .order_by(models.Tabla.snapshot_fecha.desc(), models.Tabla.snapshot_ts.desc())
                    .first()
                )
                if ultimo is None:
                    continue
                hora = hora_cambio(ultimo)
                color_tabla = (ultimo.color or "").strip().lower()
                if color_tabla != "red":
                    episodio.estado_fin = "OK"
                    episodio.fecha_actualizacion = hora
                    duracion = _formatear_duracion(episodio.fecha_hora, hora)
                    _agregar_a_descripcion(
                        episodio,
                        f" Solucionado - Estado OK a las {hora.strftime('%H:%M')}. Duración: {duracion}.",
                    )
                    corregidos += 1
                else:
                    estado_normalizado = ESTADOS_TABLA_NORMALIZADOS.get(ultimo.estado.upper().strip(), "ERROR")
                    if episodio.estado != estado_normalizado:
                        _agregar_a_descripcion(
                            episodio,
                            f" Cambió a {estado_normalizado.lower()} a las {hora.strftime('%H:%M')}.",
                        )
                        episodio.estado = estado_normalizado
                        corregidos += 1
                    episodio.fecha_actualizacion = hora

            db.commit()
        except ObjectDeletedError:
            db.rollback()
            logger.warning(
                "Episodio id %s borrado (posible purga concurrente) al resincronizar; se saltea",
                inspect(episodio).identity[0],
            )
        except Exception:
            db.rollback()
            logger.exception(
                "Fallo resincronizando episodio %s [%s] (id %s); se reintenta el proximo ciclo",
                ep_nombre, ep_tecnologia, ep_id,
            )

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
    es_demorado: bool = False,
    tipo: str = "alerta_critica",
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
        enviar_alerta_push(
            token_row.fcm_token, titulo=titulo, cuerpo=mensaje, critica=critica, es_demorado=es_demorado,
            tipo=tipo,
        )
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
    """Usado solo por el fallo silencioso (incoherencia proceso/tabla, ver
    _registrar_incoherencia): a diferencia de una alarma real de proceso
    CORE, esto es un aviso de inconsistencia de datos, no algo que amerite
    sonido de alarma ni pantalla completa -por eso va como notificacion
    normal ("alerta_normal"), no critica."""
    for usuario, token_row in _obtener_destinatarios(db):
        _intentar_push(
            db, usuario, token_row, control_id, mensaje, titulo, critica=False, tipo="alerta_normal"
        )


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
        db.flush()
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
    db.flush()


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
    _agregar_a_descripcion(abierta, f" Solucionado - Estado OK a las {ts.strftime('%H:%M')}. Duración: {duracion}.")
    db.flush()


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
        if tabla and (tabla.estado or "").strip().upper() in ESTADOS_TABLA_TRANSITORIOS:
            # Todavia esta cargando: ni se abre incoherencia nueva ni se
            # cierra una existente con este snapshot a medio camino.
            continue

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
        if proceso and recuperado_confirmado(proceso) and es_core(proceso):
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


def _vista_evento(db: Session, evento: models.CatalogoCambio):
    """Estado de un proceso/tabla EN EL MOMENTO del evento, con la misma
    forma que una fila de catalogo, para reusar _actualizar_bitacora_* y las
    revisiones de incoherencia tal cual. Los datos fijos (id, core,
    cantidad, snapshot_fecha) salen de la fila de catalogo de ese dia;
    estado, color y hora salen del evento. No sirve mirar solo la fila: si
    entre un ciclo y otro llegaron dos eventos del mismo proceso (ERROR y
    despues OK), la fila ya muestra solo el final y la bitacora tiene que
    ver los dos pasos, cada uno con su hora."""

    modelo = models.Control if evento.tipo == "PROCESO" else models.Tabla
    fila = (
        db.query(modelo)
        .filter(modelo.nombre == evento.nombre, modelo.snapshot_fecha == evento.ts.date())
        .order_by(modelo.snapshot_ts.desc())
        .first()
    )
    if fila is not None:
        datos = {c.name: getattr(fila, c.name) for c in modelo.__table__.columns}
    else:
        # Fila ya no esta (p.ej. baja a mitad del dia): la bitacora se
        # registra igual con lo que trae el evento; lo que necesita la fila
        # (incoherencia proceso/tabla) se salta.
        datos = {
            "id": None, "nombre": evento.nombre, "fuente": evento.fuente,
            "snapshot_fecha": evento.ts.date(), "core": None, "cantidad": None,
        }
    if not datos.get("fuente"):
        datos["fuente"] = evento.fuente
    datos.update(estado=evento.estado_nuevo, color=evento.color_nuevo, snapshot_ts=evento.ts, estado_ts=evento.ts)
    return SimpleNamespace(**datos)


def revisar_cambios_nuevos(db: Session) -> int:
    """Recorre los eventos de cambio de estado que OP_PROD registro en
    dataops_catalogo_cambios (id mayor al ultimo revisado) y, por cada uno,
    revisa la incoherencia proceso/tabla (fallo silencioso: proceso core en
    OK con su tabla vacia/en error, o tabla en rojo cuyo proceso dice OK).

    No escribe episodios de proceso/tabla en la bitacora: esos vienen
    replicados de MySQL en cada push (ver services/catalogos.py), con el
    mismo criterio que ve el monitor web. Tampoco envia alarmas (ver
    `revisar_alarmas_activas`): la alarma se decide mirando el estado ACTUAL
    de cada proceso en cada ciclo, no los eventos."""

    estado_poller = _obtener_o_crear_estado(db)

    nuevos = (
        db.query(models.CatalogoCambio)
        .filter(models.CatalogoCambio.id > estado_poller.ultimo_cambio_revisado)
        .order_by(models.CatalogoCambio.id.asc())
        .all()
    )
    if not nuevos:
        return 0

    procesados = 0
    for evento in nuevos:
        evento_id, nombre, tipo = evento.id, evento.nombre, evento.tipo
        try:
            vista = _vista_evento(db, evento)
            if tipo == "PROCESO":
                if vista.id is not None and color_efectivo(vista) == "green" and es_core(vista):
                    _revisar_incoherencia_desde_proceso(db, vista)
            else:
                # Si el evento es de un dia anterior (carga de ayer que llego
                # tarde), el proceso de hoy ni siquiera corrio: no es un fallo
                # silencioso nuevo. Tampoco si la tabla sigue "EN PROCESO".
                es_de_hoy = vista.snapshot_fecha == datetime.now(BOLIVIA_TZ).date()
                estado_tabla = (vista.estado or "").strip().upper()
                if (
                    (vista.color or "").strip().lower() == "red"
                    and estado_tabla not in ESTADOS_TABLA_TRANSITORIOS
                    and es_de_hoy
                ):
                    _revisar_incoherencia_desde_tabla(db, vista)

            estado_poller.ultimo_cambio_revisado = evento_id
            db.commit()
            procesados += 1
        except Exception:
            # Un dato puntual que rompe UN evento no debe frenar el cursor
            # ahi para siempre (cada ciclo volveria a explotar en el mismo
            # evento y todo lo posterior quedaria sin bitacora). Se commitea
            # evento por evento por lo mismo: el rollback de uno roto no se
            # lleva el trabajo ya bueno de los anteriores.
            db.rollback()
            logger.exception(
                "Fallo revisando el evento %s (%s %s); se salta y se sigue", evento_id, tipo, nombre
            )
            estado_poller.ultimo_cambio_revisado = evento_id
            db.commit()

    return procesados


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


def _usuarios_notificados(db: Session, episodio_id: int) -> set[int]:
    filas = (
        db.query(models.EpisodioAlertaUsuario.usuario_id)
        .filter(models.EpisodioAlertaUsuario.episodio_id == episodio_id)
        .all()
    )
    return {fila[0] for fila in filas}


def _limpiar_notificados(db: Session, episodio_id: int) -> None:
    db.query(models.EpisodioAlertaUsuario).filter(
        models.EpisodioAlertaUsuario.episodio_id == episodio_id
    ).delete()


def _disparar_alarma(db: Session, proceso: models.Control, episodio: models.EpisodioAlerta) -> bool:
    """Intenta avisar solo a los destinatarios que TODAVIA no fueron
    notificados con exito para el tramo abierto actual de este episodio
    (`EpisodioAlertaUsuario`). Antes se marcaba el episodio entero como
    "ya avisado" apenas UN destinatario recibia el push -si a otro le
    fallaba (token vencido), ese usuario en particular quedaba sin alarma
    para siempre, aunque despues arreglara su token, porque el episodio ya
    figuraba como avisado. Devuelve True si, despues de este intento, ya no
    queda nadie pendiente."""

    es_demorado = estado_efectivo(proceso) == "DEMORADO"
    es_critica = not es_demorado
    mensaje = f"[{proceso.fuente}] {proceso.nombre}: {estado_efectivo(proceso)}"
    # Esta funcion ya solo se llama para procesos core (ver
    # _revisar_alarma_de_proceso): los no-core nunca llegan aca.
    titulo = "Alerta de proceso CORE" if es_critica else "Proceso CORE demorado"

    destinatarios = _obtener_destinatarios(db)
    if not destinatarios:
        logger.warning(
            "No hay destinatarios con token FCM registrado: no se puede alarmar %s [%s]",
            proceso.nombre, proceso.fuente,
        )
        return False

    ya_notificados = _usuarios_notificados(db, episodio.id)
    pendientes = [(usuario, token_row) for usuario, token_row in destinatarios if usuario.id not in ya_notificados]
    if not pendientes:
        return True

    logger.warning(
        "Disparando alarma CORE para %s [%s] (demorado=%s) a %d destinatario(s) pendiente(s) de %d",
        proceso.nombre, proceso.fuente, es_demorado, len(pendientes), len(destinatarios),
    )

    for usuario, token_row in pendientes:
        if _intentar_push(
            db, usuario, token_row, proceso.id, mensaje, titulo, critica=es_critica, es_demorado=es_demorado
        ):
            db.add(models.EpisodioAlertaUsuario(episodio_id=episodio.id, usuario_id=usuario.id))

    return len(_usuarios_notificados(db, episodio.id)) >= len(destinatarios)


def _revisar_alarma_de_proceso(db: Session, proceso: models.Control) -> bool:
    """Decide si hace falta (re)disparar la alarma para el estado ACTUAL de
    este proceso, sin importar si esta fila es nueva o ya se habia visto
    antes. Mientras el episodio siga abierto se revisa TODOS los ciclos
    (no solo al abrirse) para poder alcanzar a quien le fallo el push la
    primera vez. Devuelve True si ya no queda nadie pendiente de avisar.

    Los procesos NO core no pasan por aca: generan demasiado ruido como
    para alarmar individualmente por cada uno (ver revisar_resumen_no_core,
    que los cuenta y avisa con un solo push agregado)."""

    if not es_core(proceso):
        return False

    color = color_efectivo(proceso)
    episodio = _obtener_episodio_alerta(db, proceso.nombre, proceso.fuente)

    if color == "green":
        if not recuperado_confirmado(proceso):
            # Color dice verde pero el estado crudo no confirma "OK": no se
            # cierra la alarma a ciegas por una inconsistencia de datos de
            # origen. Se deja el episodio (si hay) intacto, igual que un
            # color transitorio, hasta que el estado confirme el cierre real.
            logger.warning(
                "Color verde sin confirmar por estado ('%s') en %s [%s]: no se cierra la alarma",
                proceso.estado, proceso.nombre, proceso.fuente,
            )
            return False
        if episodio is not None and episodio.abierto:
            episodio.abierto = False
            episodio.cerrado_en = hora_cambio(proceso)
            _limpiar_notificados(db, episodio.id)
            logger.info("Alarma cerrada: %s [%s] volvio a verde", proceso.nombre, proceso.fuente)
        return False

    if color not in COLORES_ALERTABLES:
        # Color transitorio (p.ej. "blue"/en ejecucion durante un reintento
        # del origen): no es una falla, pero tampoco es el exito real que
        # cierra el episodio. Si se tratara como cierre (como antes), cada
        # reintento borraba la lista de notificados y la siguiente vuelta a
        # rojo reabria el episodio como si fuera una falla nueva -avisando
        # de nuevo a todos por la MISMA falla que nunca se resolvio. Se deja
        # el episodio (si hay) intacto, y no se abre uno nuevo por esto.
        return False

    episodio_nuevo = episodio is None
    reabre = episodio is not None and not episodio.abierto

    if episodio_nuevo:
        episodio = models.EpisodioAlerta(
            nombre=proceso.nombre,
            fuente=proceso.fuente,
            color=color,
            abierto=True,
            control_id_actual=proceso.id,
            primera_deteccion=hora_cambio(proceso),
        )
        db.add(episodio)
        db.flush()  # asigna episodio.id, lo necesita _disparar_alarma
        logger.warning("Nueva alarma detectada: %s [%s] en %s", proceso.nombre, proceso.fuente, estado_efectivo(proceso))
    elif reabre:
        episodio.abierto = True
        episodio.primera_deteccion = hora_cambio(proceso)
        episodio.cerrado_en = None
        _limpiar_notificados(db, episodio.id)
        logger.warning("Proceso %s [%s] volvio a fallar: reabre alarma", proceso.nombre, proceso.fuente)

    episodio.color = color
    episodio.control_id_actual = proceso.id

    exito = _disparar_alarma(db, proceso, episodio)
    episodio.ultima_alerta_en = hora_cambio(proceso)
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
            # El acceso a nombre/fuente va DENTRO del try: cada db.commit()
            # del ciclo anterior vence los objetos ya cargados, asi que
            # tocar un atributo aca dispara un SELECT fresco. Si otro
            # proceso (p.ej. la purga de snapshots viejos) borro esta fila
            # justo en el medio, ese SELECT tira ObjectDeletedError, que se
            # captura abajo para saltear solo este proceso.
            nombre, fuente = proceso.nombre, proceso.fuente
            if _revisar_alarma_de_proceso(db, proceso):
                disparadas += 1
            db.commit()
        except ObjectDeletedError:
            db.rollback()
            logger.warning(
                "Proceso borrado (posible purga concurrente) durante el ciclo del poller; se saltea"
            )
        except Exception:
            db.rollback()
            logger.exception(
                "Fallo revisando alarma de %s [%s]; se reintenta el proximo ciclo",
                nombre, fuente,
            )
    return disparadas


# Ultima hora Bolivia (0-23) en que se mando el resumen de no-core. En
# memoria (no en la base): en el peor caso, si el proceso se reinicia justo
# en el limite de una hora se manda un resumen de mas (no de menos), que es
# el lado seguro para no perder un aviso real.
_ultima_hora_resumen_no_core: int | None = None


def revisar_resumen_no_core(db: Session) -> bool:
    """Los procesos NO core no alarman individualmente (ver
    _revisar_alarma_de_proceso): en vez de un push por cada uno, se manda UN
    resumen agregado ("20 procesos en error, 15 demorados y 8 en tiempo") una
    sola vez por hora en punto (hora Bolivia, UTC-4), no cada vez que cambia
    la cuenta -asi el usuario recibe un estado global cada hora en vez de una
    notificacion por cada fluctuacion. Devuelve True si mando un resumen
    nuevo."""
    global _ultima_hora_resumen_no_core

    hora_actual = datetime.now(BOLIVIA_TZ).hour
    if hora_actual == _ultima_hora_resumen_no_core:
        return False
    _ultima_hora_resumen_no_core = hora_actual

    no_core = [p for p in _estado_actual_procesos(db) if not es_core(p)]
    if not no_core:
        return False

    demorados = sum(1 for p in no_core if estado_efectivo(p) == "DEMORADO")
    errores = sum(
        1 for p in no_core if color_efectivo(p) in COLORES_ALERTABLES
    ) - demorados
    en_tiempo = sum(1 for p in no_core if color_efectivo(p) == "green")

    mensaje = (
        f"{errores} proceso{'s' if errores != 1 else ''} en error, "
        f"{demorados} demorado{'s' if demorados != 1 else ''} y "
        f"{en_tiempo} en tiempo"
    )

    logger.warning("Resumen de no-core (hora %02d): %s", hora_actual, mensaje)

    for usuario, token_row in _obtener_destinatarios(db):
        try:
            enviar_resumen_push(token_row.fcm_token, titulo="Procesos no-core", cuerpo=mensaje)
        except messaging.UnregisteredError:
            logger.warning(
                "Token FCM de usuario %s ya no esta registrado en Firebase: se elimina",
                usuario.id,
            )
            db.delete(token_row)
        except Exception:
            logger.exception("Fallo al enviar resumen de no-core a usuario %s", usuario.id)
    db.commit()
    return True


def notificar_actualizacion_app(db: Session) -> int:
    """Manda a cada celular registrado el aviso silencioso de que hay
    catalogos nuevos (ver enviar_actualizacion_push). Se llama una vez por
    push de OP_PROD que trajo cambios. Devuelve cuantos avisos salieron."""
    enviados = 0
    for usuario, token_row in _obtener_destinatarios(db):
        try:
            enviar_actualizacion_push(token_row.fcm_token)
            enviados += 1
        except messaging.UnregisteredError:
            logger.warning("Token FCM de usuario %s ya no esta registrado en Firebase: se elimina", usuario.id)
            db.delete(token_row)
        except Exception:
            logger.exception("Fallo al avisar actualizacion de catalogos a usuario %s", usuario.id)
    db.commit()
    return enviados


# Retencion en la base de App_Control. Nadie mas purga estas tablas: antes lo
# hacia la replica de OP_PROD (catalogos: solo el dia de hoy). Los catalogos
# se guardan 60 dias como en MySQL (alcanza para el grafico de fallas y para
# resincronizar episodios); eventos y alertas, 180; la bitacora, 12 meses
# (el resumen anual compara contra el mismo periodo del anio anterior).
# MySQL conserva la bitacora completa: si hace falta mas, se vuelve a cargar.
RETENCION_CATALOGOS_DIAS = 60
RETENCION_EVENTOS_DIAS = 180
RETENCION_ALERTAS_DIAS = 180
RETENCION_BITACORA_DIAS = 365
_ultima_purga: date | None = None


def purgar_historial(db: Session, hoy: date | None = None) -> dict:
    """Borra lo mas viejo que la retencion, una vez por dia (la primera vez
    que corre el ciclo cada dia). Las filas de catalogo que todavia tienen
    alertas apuntandolas (FK) se dejan: se van solas cuando se purguen esas
    alertas, 120 dias despues."""
    global _ultima_purga

    hoy = hoy or datetime.now(BOLIVIA_TZ).date()
    if _ultima_purga == hoy:
        return {}

    limite_catalogos = hoy - timedelta(days=RETENCION_CATALOGOS_DIAS)
    limite_eventos = datetime.combine(hoy - timedelta(days=RETENCION_EVENTOS_DIAS), time.min)
    limite_alertas = datetime.combine(hoy - timedelta(days=RETENCION_ALERTAS_DIAS), time.min)
    limite_bitacora = datetime.combine(hoy - timedelta(days=RETENCION_BITACORA_DIAS), time.min)
    referenciados = select(models.Alerta.control_id)

    try:
        borrado = {
            "bitacora": db.query(models.BitacoraError)
            .filter(models.BitacoraError.fecha_hora < limite_bitacora)
            .delete(synchronize_session=False),
            "alertas": db.query(models.Alerta)
            .filter(models.Alerta.creado_en < limite_alertas)
            .delete(synchronize_session=False),
            "procesos": db.query(models.Control)
            .filter(models.Control.snapshot_fecha < limite_catalogos, models.Control.id.not_in(referenciados))
            .delete(synchronize_session=False),
            "tablas": db.query(models.Tabla)
            .filter(models.Tabla.snapshot_fecha < limite_catalogos)
            .delete(synchronize_session=False),
            "eventos": db.query(models.CatalogoCambio)
            .filter(models.CatalogoCambio.ts < limite_eventos)
            .delete(synchronize_session=False),
        }
        db.commit()
    except Exception:
        db.rollback()
        logger.exception("Fallo la purga diaria del historial; se reintenta en el proximo ciclo")
        return {}

    _ultima_purga = hoy
    if any(borrado.values()):
        logger.info("Purga diaria del historial: %s", borrado)
    return borrado
