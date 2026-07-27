import logging
from datetime import datetime, timedelta
from typing import Optional

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app import models
from app.config import settings
from app.database import get_db

logger = logging.getLogger(__name__)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


class AccesoGoogleNoConcedido(Exception):
    """Se lanza cuando una cuenta de Google es valida pero todavia no tiene
    acceso concedido (solicitud pendiente o rechazada)."""

    def __init__(self, mensaje: str):
        self.mensaje = mensaje


def verificar_password(password_plano: str, password_hash: str) -> bool:
    return pwd_context.verify(password_plano, password_hash)


def hashear_password(password: str) -> str:
    return pwd_context.hash(password)


def crear_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=settings.access_token_expire_minutes))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def autenticar_contra_monitor(username: str, password: str) -> Optional[str]:
    """Llama al mismo endpoint de login que usa el monitor web (AD + fallback interno).
    Devuelve el access_token que emite ese monitor si las credenciales son validas
    (ese mismo token sirve despues para llamar directo a sus endpoints de
    Netezza/Postgres), o None si las rechaza o el servicio no responde."""

    url = f"{settings.monitor_auth_url.rstrip('/')}/api/auth/token"
    try:
        response = httpx.post(url, json={"user": username, "password": password}, timeout=10)
        body = response.json() if response.content else {}
        if isinstance(body, dict) and body.get("ok") and body.get("access_token"):
            return body["access_token"]
        return None
    except Exception as exc:
        logger.warning("No se pudo contactar al monitor (%s): %s", url, exc)
        return None


def buscar_usuario_por_identificador(identificador: str, db: Session) -> Optional[models.Usuario]:
    """El campo de login acepta tanto el username como el correo."""
    return (
        db.query(models.Usuario)
        .filter(
            (models.Usuario.username == identificador) | (models.Usuario.email.ilike(identificador))
        )
        .first()
    )


def autenticar_usuario(identificador: str, password: str, db: Session) -> Optional[models.Usuario]:
    """Intenta primero contra el monitor (AD + su propio fallback). Si el monitor
    deniega (por ejemplo, una cuenta creada solo aca que AD no conoce), se revisa
    tambien el password_hash local antes de rechazar."""

    usuario = buscar_usuario_por_identificador(identificador, db)
    if usuario is None or not usuario.activo:
        return None

    if autenticar_contra_monitor(usuario.username, password):
        return usuario

    if usuario.password_hash and verificar_password(password, usuario.password_hash):
        return usuario

    return None


def configurar_password_local(
    identificador: str, password_actual: str, password_nueva: str, db: Session
) -> Optional[models.Usuario]:
    """Permite a un usuario (cuenta AD sin password_hash aun, o que quiere
    cambiarlo) definir su contrasena local, probando primero la actual
    (contra el monitor/AD, o contra el password_hash si ya tenia uno)."""

    usuario = buscar_usuario_por_identificador(identificador, db)
    if usuario is None or not usuario.activo:
        return None

    verificada = autenticar_contra_monitor(usuario.username, password_actual)
    if not verificada and usuario.password_hash:
        verificada = verificar_password(password_actual, usuario.password_hash)

    if not verificada:
        return None

    usuario.password_hash = hashear_password(password_nueva)
    db.commit()
    db.refresh(usuario)
    return usuario


def autenticar_con_google(id_token_str: str, db: Session) -> Optional[models.Usuario]:
    """Verifica el id_token de Google Sign-In (firma y audiencia). Si el correo ya
    es un usuario activo, deja pasar. Si no, crea/consulta una solicitud de acceso
    y lanza AccesoGoogleNoConcedido con un mensaje segun su estado."""

    try:
        payload = google_id_token.verify_oauth2_token(
            id_token_str, google_requests.Request(), audience=settings.google_oauth_client_id
        )
    except Exception as exc:
        logger.warning("Token de Google invalido: %s", exc)
        return None

    if not payload.get("email_verified"):
        return None

    email = payload["email"]
    nombre = payload.get("name")

    usuario = (
        db.query(models.Usuario)
        .filter(
            (models.Usuario.email.ilike(email))
            | (models.Usuario.email_google.ilike(email))
        )
        .first()
    )
    if usuario is not None and usuario.activo:
        return usuario

    solicitud = db.query(models.SolicitudAccesoGoogle).filter(
        models.SolicitudAccesoGoogle.email.ilike(email)
    ).first()

    if solicitud is None:
        solicitud = models.SolicitudAccesoGoogle(email=email, nombre=nombre, estado="pendiente")
        db.add(solicitud)
        db.commit()
        raise AccesoGoogleNoConcedido(
            "Tu solicitud de acceso fue enviada. Un administrador debe aprobarla."
        )

    if solicitud.estado == "rechazada":
        raise AccesoGoogleNoConcedido("Tu solicitud de acceso fue rechazada.")

    raise AccesoGoogleNoConcedido("Tu solicitud de acceso todavia esta pendiente de aprobacion.")


def es_administrador(usuario: models.Usuario, db: Session) -> bool:
    return (
        db.query(models.Administrador).filter(models.Administrador.usuario_id == usuario.id).first()
        is not None
    )


def obtener_usuario_actual(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> models.Usuario:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudo validar la credencial",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        username: Optional[str] = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    usuario = db.query(models.Usuario).filter(models.Usuario.username == username).first()
    if usuario is None:
        raise credentials_exception
    return usuario


def requerir_admin(
    usuario_actual: models.Usuario = Depends(obtener_usuario_actual),
    db: Session = Depends(get_db),
) -> models.Usuario:
    if not es_administrador(usuario_actual, db):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Requiere permisos de administrador")
    return usuario_actual
