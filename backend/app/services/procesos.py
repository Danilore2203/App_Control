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
