"""Recuperar la contrasena de la app por correo, sin saber la anterior.

1. POST /auth/recuperar con el usuario o el correo. Si la cuenta existe, esta
   activa y tiene correo, se genera un codigo de 6 digitos y se deja un
   comando `correo.recuperar_password` en la cola: OP_PROD lo retira y manda
   el correo con su SMTP (Render no tiene salida a ese servidor de correo).
   La respuesta es siempre la misma, exista o no la cuenta.
2. POST /auth/restablecer con el usuario, el codigo y la contrasena nueva.

Del codigo solo se guarda un HMAC (con la clave de los JWT). Vence a los 15
minutos, sirve una vez, se anula despues de 5 intentos fallidos y se pueden
pedir como mucho 3 por hora: adivinarlo es del orden de 1 en 70.000 por hora
para una cuenta. Pedir uno nuevo anula el anterior.
"""
import hashlib
import hmac
import json
import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy.orm import Session

from app import auth, models
from app.config import settings

logger = logging.getLogger(__name__)

TIPO_COMANDO = "correo.recuperar_password"
MINUTOS_VIGENCIA = 15
MAX_INTENTOS = 5
MAX_CODIGOS_POR_HORA = 3


def _hash_codigo(usuario_id: int, codigo: str) -> str:
    return hmac.new(
        settings.jwt_secret.encode(), f"{usuario_id}:{codigo}".encode(), hashlib.sha256
    ).hexdigest()


def _correo(usuario: models.Usuario) -> Optional[str]:
    return (usuario.email or usuario.email_google or "").strip() or None


def solicitar(db: Session, identificador: str, ahora: Optional[datetime] = None) -> bool:
    """True si se pidio el correo. Quien llama no le cuenta el resultado al
    usuario (asi no se puede averiguar que cuentas existen)."""
    ahora = ahora or datetime.utcnow()
    usuario = auth.buscar_usuario_por_identificador(identificador.strip(), db)
    if usuario is None or not usuario.activo:
        return False
    para = _correo(usuario)
    if not para:
        logger.info("Recuperacion pedida para %s, que no tiene correo", usuario.username)
        return False

    codigos = db.query(models.CodigoRecuperacion).filter(models.CodigoRecuperacion.usuario_id == usuario.id)
    recientes = codigos.filter(models.CodigoRecuperacion.creado_en >= ahora - timedelta(hours=1)).count()
    if recientes >= MAX_CODIGOS_POR_HORA:
        logger.info("Recuperacion de %s: ya pidio %s codigos en la ultima hora", usuario.username, recientes)
        return False

    codigos.filter(models.CodigoRecuperacion.usado_en.is_(None)).update(
        {models.CodigoRecuperacion.usado_en: ahora}, synchronize_session=False
    )
    codigo = f"{secrets.randbelow(10**6):06d}"
    db.add(
        models.CodigoRecuperacion(
            usuario_id=usuario.id,
            codigo_hash=_hash_codigo(usuario.id, codigo),
            creado_en=ahora,
            expira_en=ahora + timedelta(minutes=MINUTOS_VIGENCIA),
            intentos=0,
        )
    )
    db.add(
        models.Comando(
            tipo=TIPO_COMANDO,
            payload=json.dumps(
                {
                    "para": para,
                    "nombre": usuario.nombre or usuario.username,
                    "usuario": usuario.username,
                    "codigo": codigo,
                    "minutos": MINUTOS_VIGENCIA,
                },
                ensure_ascii=False,
            ),
            estado="pendiente",
            creado_por_id=usuario.id,
            creado_en=ahora,
        )
    )
    db.commit()
    return True


def restablecer(
    db: Session, identificador: str, codigo: str, password_nueva: str, ahora: Optional[datetime] = None
) -> Optional[models.Usuario]:
    """Cambia la contrasena si el codigo es el ultimo pedido, no vencio ni se
    uso. Devuelve el usuario, o None con cualquier problema (sin decir cual)."""
    ahora = ahora or datetime.utcnow()
    usuario = auth.buscar_usuario_por_identificador(identificador.strip(), db)
    if usuario is None or not usuario.activo:
        return None

    fila = (
        db.query(models.CodigoRecuperacion)
        .filter(
            models.CodigoRecuperacion.usuario_id == usuario.id,
            models.CodigoRecuperacion.usado_en.is_(None),
        )
        .order_by(models.CodigoRecuperacion.creado_en.desc(), models.CodigoRecuperacion.id.desc())
        .first()
    )
    if fila is None or fila.expira_en < ahora or fila.intentos >= MAX_INTENTOS:
        return None

    if not hmac.compare_digest(fila.codigo_hash, _hash_codigo(usuario.id, codigo.strip())):
        fila.intentos += 1
        if fila.intentos >= MAX_INTENTOS:
            fila.usado_en = ahora
        db.commit()
        return None

    fila.usado_en = ahora
    # Solo password_hash: password_hash_web queda como estaba, asi el proximo
    # push de la web no la pisa (solo lo haria si alguien la cambia alla).
    usuario.password_hash = auth.hashear_password(password_nueva)
    db.commit()
    db.refresh(usuario)
    logger.info("Contrasena de %s cambiada con codigo de recuperacion", usuario.username)
    return usuario
