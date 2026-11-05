"""Un ciclo del poller: alarmas, resumen no-core, bitacora desde los eventos,
resincronizacion de episodios y purga diaria. Vive aparte de main.py para
poder dispararlo desde dos lugares: el timer de respaldo (lifespan) y,
sobre todo, apenas llega un push de OP_PROD (POST /internal/catalogos),
que es cuando de verdad hay algo nuevo que mirar."""
import logging
import threading

from sqlalchemy import text

from app.database import PollerSessionLocal, engine
from app.services.poller import (
    notificar_actualizacion_app,
    purgar_historial,
    resincronizar_episodios_abiertos,
    revisar_alarmas_activas,
    revisar_cambios_nuevos,
    revisar_resumen_no_core,
)

logger = logging.getLogger(__name__)

# Clave arbitraria para el advisory lock de Postgres (pg_try_advisory_lock usa
# un bigint como namespace propio, no colisiona con nada mas de la base).
_POLLER_LOCK_KEY = 892375100

# Dentro de UN proceso: el timer y un push pueden coincidir; el segundo
# simplemente se salta (el que esta corriendo ya va a ver los datos nuevos,
# o los vera el siguiente).
_lock_proceso = threading.Lock()


def _correr_ciclo(db, avisar_app: bool) -> None:
    # Va primero y no depende de las otras: decide la alarma mirando el
    # estado ACTUAL de cada proceso, no el cursor de bitacora, para que una
    # falla en las otras nunca le cueste una alarma real al usuario.
    revisar_alarmas_activas(db)
    revisar_resumen_no_core(db)
    revisar_cambios_nuevos(db)
    resincronizar_episodios_abiertos(db)
    purgar_historial(db)
    if avisar_app:
        # Al final, para que cuando la app vuelva a pedir /controles y la
        # bitacora ya esten las alarmas y episodios de este push.
        notificar_actualizacion_app(db)


def ejecutar_ciclo(avisar_app: bool = False) -> bool:
    """Corre un ciclo completo. `avisar_app`: ademas, al terminar, manda a
    los celulares el aviso silencioso de que hay datos nuevos (solo tiene
    sentido cuando el ciclo lo disparo un push con cambios). Devuelve False
    si se salto porque otro ciclo ya estaba corriendo (en este proceso o en
    otra instancia)."""
    if not _lock_proceso.acquire(blocking=False):
        logger.info("Ya hay un ciclo del poller corriendo en este proceso; se salta")
        return False
    try:
        # Advisory lock a nivel de sesion: si Railway solapa dos instancias
        # durante un redeploy (la vieja se apaga mientras la nueva ya
        # arranco), sin esto ambas leen el mismo cursor y cada una crea su
        # propia fila para el mismo evento -bitacora duplicada. La instancia
        # que no lo consigue se salta este ciclo.
        conn = engine.connect()
        try:
            adquirido = conn.execute(
                text("SELECT pg_try_advisory_lock(:clave)"), {"clave": _POLLER_LOCK_KEY}
            ).scalar()
            if not adquirido:
                logger.info("Otra instancia ya tiene el poller corriendo; se salta este ciclo")
                return False
            db = PollerSessionLocal()
            try:
                _correr_ciclo(db, avisar_app)
            finally:
                db.close()
        finally:
            try:
                conn.execute(text("SELECT pg_advisory_unlock(:clave)"), {"clave": _POLLER_LOCK_KEY})
            except Exception:
                # El lock es de SESION: si no se pudo soltar, la conexion no
                # puede volver al pool con el lock tomado (todos los ciclos
                # siguientes creerian que "otra instancia" lo tiene, para
                # siempre). Se invalida para que el pool la descarte y
                # Postgres libere el lock al cerrarse de verdad.
                logger.warning("No se pudo soltar el advisory lock; se descarta la conexion")
                conn.invalidate()
            conn.close()
    finally:
        _lock_proceso.release()
    return True


def _ciclo_seguro(avisar_app: bool) -> None:
    try:
        if not ejecutar_ciclo(avisar_app) and avisar_app:
            # Se salto porque otro ciclo ya corria: ese ciclo no sabe que
            # hay que avisar a la app. El timer de respaldo no avisa, asi
            # que se reintenta en breve para no dejar la app sin refresco.
            threading.Timer(5.0, _ciclo_seguro, args=(True,)).start()
    except Exception:
        logger.exception("El ciclo del poller disparado por un push fallo; el timer lo reintenta")


def ejecutar_ciclo_en_segundo_plano(avisar_app: bool) -> None:
    """Para el endpoint de push: responde a OP_PROD enseguida y procesa los
    datos nuevos en un hilo aparte."""
    threading.Thread(target=_ciclo_seguro, args=(avisar_app,), name="ciclo-poller", daemon=True).start()
