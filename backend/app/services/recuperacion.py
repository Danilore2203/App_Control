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
MINUTOS_VIGENCIA_ADMIN = 30  # el que genera un administrador: hay que pasarlo a mano
MAX_INTENTOS = 5
MAX_CODIGOS_POR_HORA = 3


def _hash_codigo(usuario_id: int, codigo: str) -> str:
    return hmac.new(
        settings.jwt_secret.encode(), f"{usuario_id}:{codigo}".encode(), hashlib.sha256
    ).hexdigest()


def _correo(usuario: models.Usuario) -> Optional[str]:
    return (usuario.email or usuario.email_google or "").strip() or None


def _correos_de(db: Session, usuario_id: int, desde: datetime):
    return db.query(models.Comando).filter(
        models.Comando.tipo == TIPO_COMANDO,
        models.Comando.creado_por_id == usuario_id,
        models.Comando.creado_en >= desde,
    )


def _codigos_que_cuentan(db: Session, usuario_id: int, ahora: datetime) -> int:
    """Codigos de la ultima hora para el limite, sin contar los que nunca
    salieron (OP_PROD caido, sin reiniciar o con el SMTP fallando): si no, un
    problema del servidor dejaba al usuario una hora sin poder pedir otro."""
    desde = ahora - timedelta(hours=1)
    pedidos = (
        db.query(models.CodigoRecuperacion)
        .filter(models.CodigoRecuperacion.usuario_id == usuario_id, models.CodigoRecuperacion.creado_en >= desde)
        .count()
    )
    fallidos = _correos_de(db, usuario_id, desde).filter(models.Comando.estado.in_(("error", "expirado"))).count()
    return max(pedidos - fallidos, 0)


def _tapar(correo: str) -> str:
    usuario, _, dominio = correo.partition("@")
    return f"{usuario[:1]}***@{dominio}" if dominio else "***"


def diagnostico(db: Session, identificador: str, ahora: Optional[datetime] = None) -> dict:
    """Para soporte (GET /internal/recuperacion/estado, con la clave interna):
    por que no llega el correo de una cuenta. Sin el codigo y con el correo
    tapado."""
    ahora = ahora or datetime.utcnow()
    usuario = auth.buscar_usuario_por_identificador(identificador.strip(), db)
    if usuario is None:
        return {"encontrado": False}
    para = _correo(usuario)
    cuentan = _codigos_que_cuentan(db, usuario.id, ahora)
    correos = (
        _correos_de(db, usuario.id, ahora - timedelta(days=1)).order_by(models.Comando.creado_en.desc()).limit(10).all()
    )
    return {
        "encontrado": True,
        "username": usuario.username,
        "activo": bool(usuario.activo),
        "correo": _tapar(para) if para else None,
        "codigos_ultima_hora": cuentan,
        "puede_pedir": bool(usuario.activo and para and cuentan < MAX_CODIGOS_POR_HORA),
        "correos_24h": [
            {
                "id": c.id,
                "estado": c.estado,
                "creado_en": c.creado_en.isoformat() if c.creado_en else None,
                "terminado_en": c.terminado_en.isoformat() if c.terminado_en else None,
                "error": c.error,
                "resultado": c.resultado,
            }
            for c in correos
        ],
    }


def _anular_anteriores(db: Session, usuario_id: int, ahora: datetime) -> None:
    """Un codigo nuevo deja sin efecto los anteriores de la cuenta."""
    db.query(models.CodigoRecuperacion).filter(
        models.CodigoRecuperacion.usuario_id == usuario_id, models.CodigoRecuperacion.usado_en.is_(None)
    ).update({models.CodigoRecuperacion.usado_en: ahora}, synchronize_session=False)
    # El correo anterior que todavia espera en la cola llevaria un codigo ya
    # anulado: no se manda (si no, llegan dos correos y el primero no sirve).
    for viejo in _correos_de(db, usuario_id, ahora - timedelta(days=1)).filter(models.Comando.estado == "pendiente"):
        viejo.estado = "cancelado"  # no es una falla: sigue contando para el limite por hora
        viejo.terminado_en = ahora
        viejo.error = "Reemplazado por un pedido nuevo"
        viejo.payload = json.dumps({**json.loads(viejo.payload or "{}"), "codigo": "***"}, ensure_ascii=False)


def generar_por_admin(
    db: Session, usuario: models.Usuario, admin: models.Usuario, ahora: Optional[datetime] = None
) -> tuple[str, datetime]:
    """Un administrador genera el codigo y se lo pasa a la persona (Teams, en
    persona): sirve cuando el correo no llega. La persona elige su contrasena
    en la app con ese codigo, asi el administrador nunca la conoce. Vale
    MINUTOS_VIGENCIA_ADMIN, una sola vez, con el mismo limite de intentos."""
    ahora = ahora or datetime.utcnow()
    _anular_anteriores(db, usuario.id, ahora)
    codigo = f"{secrets.randbelow(10**6):06d}"
    expira = ahora + timedelta(minutes=MINUTOS_VIGENCIA_ADMIN)
    db.add(
        models.CodigoRecuperacion(
            usuario_id=usuario.id,
            codigo_hash=_hash_codigo(usuario.id, codigo),
            creado_en=ahora,
            expira_en=expira,
            intentos=0,
        )
    )
    db.commit()
    logger.info("Codigo de recuperacion para %s generado por el administrador %s", usuario.username, admin.username)
    return codigo, expira


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

    recientes = _codigos_que_cuentan(db, usuario.id, ahora)
    if recientes >= MAX_CODIGOS_POR_HORA:
        logger.info("Recuperacion de %s: ya pidio %s codigos en la ultima hora", usuario.username, recientes)
        return False

    _anular_anteriores(db, usuario.id, ahora)
    codigo = f"{secrets.randbelow(10**6):06d}"
    comando = models.Comando(
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
    db.add(comando)
    db.flush()
    db.add(
        models.CodigoRecuperacion(
            usuario_id=usuario.id,
            codigo_hash=_hash_codigo(usuario.id, codigo),
            creado_en=ahora,
            expira_en=ahora + timedelta(minutes=MINUTOS_VIGENCIA),
            intentos=0,
            comando_id=comando.id,
        )
    )
    db.commit()
    return True


def correo_enviado(db: Session, comando_id: int, cuando: Optional[datetime]) -> None:
    """OP_PROD mando el correo: los 15 minutos del codigo cuentan desde ahora
    (si OP tardo en mandarlo, la persona igual tiene su tiempo completo)."""
    cuando = cuando or datetime.utcnow()
    fila = (
        db.query(models.CodigoRecuperacion)
        .filter(models.CodigoRecuperacion.comando_id == comando_id, models.CodigoRecuperacion.usado_en.is_(None))
        .first()
    )
    if fila is not None:
        fila.expira_en = max(fila.expira_en, cuando + timedelta(minutes=MINUTOS_VIGENCIA))


def envio_disponible(db: Session) -> bool:
    """Si hay un OP_PROD atendiendo que sabe mandar este correo."""
    from app.services import comandos

    return comandos.op_atiende(db, TIPO_COMANDO)


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
