from slowapi import Limiter
from slowapi.util import get_remote_address

# Compartido entre main.py (registra el manejador de error) y los routers
# que necesiten limitar por IP (por ahora, solo auth: son los unicos
# endpoints expuestos a intentos de fuerza bruta sin sesion previa).
limiter = Limiter(key_func=get_remote_address)
