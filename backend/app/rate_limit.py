from slowapi import Limiter
from slowapi.util import get_remote_address
from starlette.requests import Request


def _ip_del_cliente(request: Request) -> str:
    """get_remote_address usa request.client.host, que es la IP del proxy de
    Railway (no la del cliente real) porque la app corre detras de su edge
    proxy: sin esto, todos los usuarios comparten el mismo limite "por IP"
    -un solo actor puede agotar el cupo de /auth/login para todos. Railway
    agrega la IP real como primer valor de X-Forwarded-For."""

    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return get_remote_address(request)


# Compartido entre main.py (registra el manejador de error) y los routers
# que necesiten limitar por IP (por ahora, solo auth: son los unicos
# endpoints expuestos a intentos de fuerza bruta sin sesion previa).
limiter = Limiter(key_func=_ip_del_cliente)
