"""Reglas propias de esta app sobre procesos, que no vienen ya resueltas
desde dataops_catalogo_procesos (que es de solo lectura, no se altera)."""


def es_core(proceso) -> bool:
    return (proceso.core or "").strip().upper() == "SI"


def _demorado(proceso) -> bool:
    """DEMORADO (naranja) ya paso su hora_fin -asi lo marca el origen-, asi
    que para esta app eso es una falla real, no una simple demora. Aplica a
    cualquier proceso, no solo a los core (los core ademas disparan alarma
    de pantalla completa y el chequeo de incoherencia, eso si es aparte)."""
    return proceso.color == "orange"


def color_efectivo(proceso) -> str:
    return "red" if _demorado(proceso) else proceso.color


def estado_efectivo(proceso) -> str:
    return "DEMORADO" if _demorado(proceso) else proceso.estado
