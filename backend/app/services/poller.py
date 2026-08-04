import logging
from datetime import datetime, timedelta, timezone

from firebase_admin import messaging
from sqlalchemy import func
from sqlalchemy.orm import Session

from app import models
from app.services.fcm import enviar_alerta_push, enviar_resumen_push
from app.services.procesos import color_efectivo, es_core, estado_efectivo, recuperado_confirmado

logger = logging.getLogger(__name__)

COLORES_ALERTABLES = {"red", "orange"}
BOLIVIA_TZ = timezone(timedelta(hours=-4))
TECNOLOGIAS_PROCESO_VALIDAS = {"AIRFLOW", "DATASTAGE", "PENTAHO"}
TECNOLOGIAS_TABLA_VALIDAS = {"QA_CONTROL", "PG_PROD"}
ESTADOS_TABLA_NORMALIZADOS = {
    "ERROR": "ERROR",
    "VACIA": "VACIA",
    "VACÍA": "VACIA",
}
# Tabla todavia cargando: ni error ni exito, no se registra ni se alerta.
ESTADOS_TABLA_TRANSITORIOS = {"EN PROCESO"}


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
    igual como ADVERTENCIA en vez de perderse en silencio.

    Termina con un flush (no un commit: eso lo sigue haciendo el que llama,
    una sola vez para todo el lote) para que, si el MISMO proceso aparece
    mas de una vez en el mismo lote de "nuevos" (p.ej. reintenta rapido y
    cambia de estado mas de una vez entre un ciclo del poller y el otro),
    la proxima llamada a _episodio_abierto() vea el episodio recien
    creado/cerrado en vez de una foto vieja de la base. SessionLocal usa
    autoflush=False, asi que sin esto una fila nueva quedaba sin guardar en
    la base hasta el commit final del lote entero, y la siguiente vez que
    este mismo proceso volvia a cambiar de estado en el mismo lote, la
    consulta no la encontraba -perdiendo o duplicando el episodio segun el
    orden exacto de los cambios."""

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
        db.flush()
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
        if recuperado_confirmado(proceso):
            episodio_abierto.fecha_actualizacion = proceso.snapshot_ts
            episodio_abierto.estado_fin = "OK"
            duracion = _formatear_duracion(episodio_abierto.fecha_hora, proceso.snapshot_ts)
            episodio_abierto.descripcion += (
                f" Solucionado - Estado OK a las {proceso.snapshot_ts.strftime('%H:%M')}. Duración: {duracion}."
            )
        else:
            # Color dice verde pero el estado crudo no confirma "OK": no
            # llegaron bien los datos de origen. No se cierra a ciegas -mejor
            # de mas que perder de vista un fallo que en realidad sigue.
            episodio_abierto.fecha_actualizacion = proceso.snapshot_ts
            if episodio_abierto.estado != "INCONSISTENTE":
                episodio_abierto.descripcion += (
                    f" Color verde pero estado '{proceso.estado}' no confirma OK a las "
                    f"{proceso.snapshot_ts.strftime('%H:%M')}: no se cierra por inconsistencia de datos."
                )
                episodio_abierto.estado = "INCONSISTENTE"

    db.flush()


def _actualizar_bitacora_tabla(db: Session, tabla: models.Tabla) -> None:
    """Misma logica de episodio que _actualizar_bitacora_proceso, mirando
    dataops_catalogo_tablas en vez de dataops_catalogo_procesos. El color se
    normaliza (strip + lower) por la misma razon que en procesos.py: el
    origen no siempre lo escribe con la misma capitalizacion.

    Mismo flush final que _actualizar_bitacora_proceso, y por la misma
    razon: sin el, dos filas nuevas de la MISMA tabla en el mismo lote no se
    ven entre si (SessionLocal usa autoflush=False)."""

    color_tabla = (tabla.color or "").strip().lower()
    estado_tabla = (tabla.estado or "").strip().upper()
    if estado_tabla in ESTADOS_TABLA_TRANSITORIOS:
        return

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
        db.flush()
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

    db.flush()


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
            if color_tabla != "red":
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
    abierta.descripcion += f" Solucionado - Estado OK a las {ts.strftime('%H:%M')}. Duración: {duracion}."
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
        try:
            color = color_efectivo(proceso)

            if proceso.fuente in TECNOLOGIAS_PROCESO_VALIDAS:
                _actualizar_bitacora_proceso(db, proceso)

            if color == "green" and es_core(proceso):
                _revisar_incoherencia_desde_proceso(db, proceso)

            estado_poller.ultimo_id_revisado = proceso.id
            db.commit()
            procesos_procesados += 1
        except Exception:
            # Sin esto, un dato puntual que rompe UN proceso (nombre/estado
            # raro, lo que sea) frenaba el cursor ahi mismo para siempre: cada
            # ciclo siguiente volvia a intentar la misma fila, volvia a
            # explotar antes de llegar al commit, y TODO lo que estaba
            # despues en la cola (de cualquier otro proceso) se quedaba sin
            # sincronizar a la bitacora indefinidamente, mientras Controles
            # (que lee el estado en vivo, sin pasar por este cursor) seguia
            # mostrando todo bien. Se commitea proceso por proceso (no una
            # sola vez al final) para que el rollback de una fila rota no se
            # lleve puesto el trabajo ya bueno de las filas anteriores del
            # mismo lote.
            db.rollback()
            logger.exception(
                "Fallo actualizando bitacora/incoherencia para %s [%s] (id %s); se salta y se sigue",
                proceso.nombre, proceso.fuente, proceso.id,
            )
            estado_poller.ultimo_id_revisado = proceso.id
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
            episodio.cerrado_en = proceso.snapshot_ts
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
            primera_deteccion=proceso.snapshot_ts,
        )
        db.add(episodio)
        db.flush()  # asigna episodio.id, lo necesita _disparar_alarma
        logger.warning("Nueva alarma detectada: %s [%s] en %s", proceso.nombre, proceso.fuente, estado_efectivo(proceso))
    elif reabre:
        episodio.abierto = True
        episodio.primera_deteccion = proceso.snapshot_ts
        episodio.cerrado_en = None
        _limpiar_notificados(db, episodio.id)
        logger.warning("Proceso %s [%s] volvio a fallar: reabre alarma", proceso.nombre, proceso.fuente)

    episodio.color = color
    episodio.control_id_actual = proceso.id

    exito = _disparar_alarma(db, proceso, episodio)
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

    procesadas = 0

    for tabla in nuevas:
        try:
            if tabla.fuente in TECNOLOGIAS_TABLA_VALIDAS:
                _actualizar_bitacora_tabla(db, tabla)

            es_de_hoy = tabla.snapshot_fecha == datetime.now(BOLIVIA_TZ).date()
            estado_tabla = (tabla.estado or "").strip().upper()
            if (
                (tabla.color or "").strip().lower() == "red"
                and estado_tabla not in ESTADOS_TABLA_TRANSITORIOS
                and es_de_hoy
            ):
                # Si el snapshot es de un dia anterior (p.ej. la carga de
                # ayer que llego tarde o quedo colgada, y hoy todavia no se
                # actualizo), el proceso de hoy ni siquiera corrio aun: no es
                # un fallo silencioso nuevo, es una fila vieja. Alertar aca
                # seria un falso positivo -se espera a que llegue un
                # snapshot con fecha de hoy. Tampoco alerta si la tabla
                # sigue "EN PROCESO": todavia esta cargando, el rojo es
                # transitorio, no un fallo.
                _revisar_incoherencia_desde_tabla(db, tabla)

            estado_poller.ultimo_id_tablas_revisado = tabla.id
            db.commit()
            procesadas += 1
        except Exception:
            # Mismo motivo que en revisar_procesos_nuevos: commitear una
            # tabla a la vez para que una fila rota no trabe el cursor (ni
            # se lleve puesto el trabajo ya bueno de las tablas anteriores
            # del mismo lote al hacer rollback).
            db.rollback()
            logger.exception(
                "Fallo actualizando bitacora/incoherencia para tabla %s [%s] (id %s); se salta y se sigue",
                tabla.nombre, tabla.fuente, tabla.id,
            )
            estado_poller.ultimo_id_tablas_revisado = tabla.id
            db.commit()

    return procesadas
