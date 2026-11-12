"""Alarmas de infraestructura que no son de un proceso: hoy, congestion en
Netezza (bloqueos pesados, muchas sesiones esperando, consultas en cola).

OP_PROD las detecta adentro de la red (dataops_monitor/vigia_netezza.py) y
avisa por POST /internal/alertas/infra con {clave, activa, titulo, mensaje}:

- Se abre (activa y no estaba abierta): alarma CRITICA de guardia a todos los
  que tienen la app (tipo "alerta_critica": en el celular suena a pantalla
  completa si la guardia esta armada y en horario; si no, notificacion).
- Sigue abierta: se actualiza el mensaje y cada RECORDAR_CADA se manda un
  recordatorio (notificacion comun, sin alarma).
- Se cierra (activa false estando abierta): aviso comun «se normalizo».

Cada cambio queda en el historial (AlertaInfraEvento), que la app muestra en
Alertas. No usa la tabla `alertas` porque esa exige un proceso.
"""
import logging
from datetime import datetime, timedelta
from typing import Optional

from firebase_admin import messaging
from sqlalchemy.orm import Session

from app import models, schemas
from app.services.fcm import enviar_alerta_push

logger = logging.getLogger(__name__)

RECORDAR_CADA = timedelta(minutes=30)


def _destinatarios(db: Session):
    return (
        db.query(models.Usuario, models.UsuarioFcmToken)
        .join(models.UsuarioFcmToken, models.UsuarioFcmToken.usuario_id == models.Usuario.id)
        .filter(models.Usuario.activo.is_(True))
        .all()
    )


def _avisar(db: Session, titulo: str, mensaje: str, critica: bool) -> int:
    """Un intento de push a cada destinatario. Devuelve a cuantos llego."""
    enviados = 0
    for usuario, token_row in _destinatarios(db):
        try:
            enviar_alerta_push(
                token_row.fcm_token,
                titulo=titulo,
                cuerpo=mensaje,
                critica=critica,
                tipo="alerta_critica" if critica else "alerta_normal",
            )
            enviados += 1
        except messaging.UnregisteredError:
            logger.warning("Token FCM de usuario %s ya no esta registrado: se elimina", usuario.id)
            db.delete(token_row)
        except Exception:
            logger.exception("Fallo el push de alarma de infraestructura a usuario %s", usuario.id)
    return enviados


def _evento(db: Session, clave: str, tipo: str, titulo: Optional[str], mensaje: Optional[str], ahora: datetime) -> None:
    db.add(models.AlertaInfraEvento(clave=clave, tipo=tipo, titulo=titulo, mensaje=mensaje, creado_en=ahora))


def registrar(db: Session, entrada: schemas.AlertaInfraIn, ahora: Optional[datetime] = None) -> schemas.AlertaInfraOut:
    ahora = ahora or datetime.utcnow()
    fila = db.get(models.AlertaInfra, entrada.clave)
    if fila is None:
        fila = models.AlertaInfra(clave=entrada.clave, abierta=False)
        db.add(fila)
    titulo = entrada.titulo.strip() or fila.titulo or entrada.clave
    mensaje = entrada.mensaje.strip() or fila.mensaje or ""

    if entrada.activa:
        if not fila.abierta:
            fila.abierta = True
            fila.abierta_en = ahora
            fila.cerrada_en = None
            fila.titulo, fila.mensaje, fila.actualizada_en = titulo, mensaje, ahora
            _evento(db, fila.clave, "abre", titulo, mensaje, ahora)
            n = _avisar(db, titulo, mensaje, critica=True)
            fila.ultimo_aviso_en = ahora
            logger.warning("Alarma de infraestructura %s abierta (avisada a %d): %s", fila.clave, n, mensaje)
        else:
            fila.titulo, fila.mensaje, fila.actualizada_en = titulo, mensaje, ahora
            if fila.ultimo_aviso_en is None or ahora - fila.ultimo_aviso_en >= RECORDAR_CADA:
                minutos = int((ahora - (fila.abierta_en or ahora)).total_seconds() // 60)
                recordatorio = f"Sigue hace {minutos} min. {mensaje}".strip()
                _evento(db, fila.clave, "sigue", titulo, recordatorio, ahora)
                _avisar(db, f"Sigue: {titulo}", recordatorio, critica=False)
                fila.ultimo_aviso_en = ahora
    elif fila.abierta:
        fila.abierta = False
        fila.cerrada_en = ahora
        fila.actualizada_en = ahora
        minutos = int((ahora - (fila.abierta_en or ahora)).total_seconds() // 60)
        cierre = entrada.mensaje.strip() or f"Se normalizó después de {minutos} min."
        titulo_cierre = entrada.titulo.strip() or f"Resuelto: {fila.titulo or fila.clave}"
        _evento(db, fila.clave, "cierra", titulo_cierre, cierre, ahora)
        _avisar(db, titulo_cierre, cierre, critica=False)
        logger.info("Alarma de infraestructura %s cerrada", fila.clave)

    db.commit()
    db.refresh(fila)
    return schemas.AlertaInfraOut.model_validate(fila)


def listar(db: Session, limite: int = 30) -> schemas.AlertasInfraOut:
    activas = db.query(models.AlertaInfra).filter(models.AlertaInfra.abierta.is_(True)).all()
    eventos = (
        db.query(models.AlertaInfraEvento)
        .order_by(models.AlertaInfraEvento.creado_en.desc(), models.AlertaInfraEvento.id.desc())
        .limit(limite)
        .all()
    )
    return schemas.AlertasInfraOut(
        activas=[schemas.AlertaInfraOut.model_validate(a) for a in activas],
        eventos=[schemas.AlertaInfraEventoOut.model_validate(e) for e in eventos],
    )
