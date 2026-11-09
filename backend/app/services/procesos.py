"""Reglas propias de esta app sobre procesos, que no vienen ya resueltas
desde dataops_catalogo_procesos (que es de solo lectura, no se altera)."""


def _color_normalizado(proceso) -> str:
    """AIRFLOW/DATASTAGE/PENTAHO no escriben el color siempre con la misma
    capitalizacion/espacios (p.ej. "Red", "RED ", " red"). Compararlo tal
    cual contra "red"/"orange"/"green" hacia que esos casos cayeran en la
    rama de color desconocido (ADVERTENCIA) aunque el proceso sea un caso
    perfectamente normal -eso rompia tanto la alarma (nunca se reconocia
    como alertable) como la bitacora (quedaba una entrada de advertencia
    confusa en vez de reflejar el estado real)."""
    return (proceso.color or "").strip().lower()


def es_core(proceso) -> bool:
    return (proceso.core or "").strip().upper() == "SI"


def _demorado(proceso) -> bool:
    """DEMORADO (naranja) ya paso su hora_fin -asi lo marca el origen-, asi
    que para esta app eso es una falla real, no una simple demora. Aplica a
    cualquier proceso, no solo a los core (los core ademas disparan alarma
    de pantalla completa y el chequeo de incoherencia, eso si es aparte)."""
    return _color_normalizado(proceso) == "orange"


def color_efectivo(proceso) -> str:
    return "red" if _demorado(proceso) else _color_normalizado(proceso)


def estado_efectivo(proceso) -> str:
    return "DEMORADO" if _demorado(proceso) else proceso.estado


def recuperado_confirmado(proceso) -> bool:
    """No alcanza con el color para dar un proceso por resuelto: si la fuente
    manda color=green pero el estado crudo no confirma "OK", es una
    inconsistencia de los datos de origen (no llegaron bien), no un exito
    real. Mejor seguir alertando de mas que cerrar un fallo que en realidad
    sigue."""
    return color_efectivo(proceso) == "green" and (proceso.estado or "").strip().upper() == "OK"


# Vigencia de la ultima corrida recibida del Monitor Airflow: si hace mas de
# esto que no llega nada, se vuelve a lo que diga el catalogo.
VIGENCIA_ESTADO_AIRFLOW_MINUTOS = 30


def clasificar_por_ultima_corrida(last_state: str | None) -> tuple[str, str] | None:
    """(color, estado) segun la ultima corrida, como el Monitor Airflow; None
    si no hay corrida que clasifique (queda lo del catalogo)."""
    estado = (last_state or "").strip().lower()
    if estado == "success":
        return "green", "OK"
    if estado == "failed":
        return "red", "ERROR"
    if estado == "running":
        return "blue", "RUNNING"
    return None


def aplicar_estados_airflow(db, controles: list, ahora=None) -> int:
    """Sobre la salida de /controles: a los DAGs de AIRFLOW que el catalogo
    dejo en gris (PAUSADO / SIN EJECUCION) les aplica la ultima corrida
    recibida del Monitor Airflow, si esa informacion es reciente. Devuelve
    cuantos cambiaron."""
    from datetime import datetime, timedelta

    from app import models

    ahora = ahora or datetime.utcnow()
    grises = [c for c in controles if c.fuente == "AIRFLOW" and (c.color or "").lower() == "gray"]
    if not grises:
        return 0
    ultimo = db.query(models.AirflowEstado.actualizado_en).order_by(models.AirflowEstado.actualizado_en.desc()).first()
    if not ultimo or ultimo[0] < ahora - timedelta(minutes=VIGENCIA_ESTADO_AIRFLOW_MINUTOS):
        return 0
    nombres = [c.nombre for c in grises]
    estados = {e.dag_id: e.last_state for e in db.query(models.AirflowEstado).filter(models.AirflowEstado.dag_id.in_(nombres)).all()}
    cambiados = 0
    for c in grises:
        nuevo = clasificar_por_ultima_corrida(estados.get(c.nombre))
        if nuevo is None:
            continue
        c.color, c.estado = nuevo
        cambiados += 1
    return cambiados
