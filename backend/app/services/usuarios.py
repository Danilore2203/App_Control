"""Altas de usuarios que no pasan por el flujo normal de solicitud/aprobacion."""
import re

from sqlalchemy import func
from sqlalchemy.orm import Session

from app import models


def generar_username(email: str, db: Session) -> str:
    base = re.sub(r"[^A-Za-z0-9_.]", "", email.split("@")[0]) or "usuario"
    if not base[0].isalpha():
        base = f"u{base}"
    base = base[:90]

    username = base
    sufijo = 1
    while db.query(models.Usuario).filter(models.Usuario.username == username).first():
        sufijo += 1
        username = f"{base}{sufijo}"
    return username


def designar_administrador(db: Session, email: str, nombre: str | None = None) -> models.Usuario:
    """Deja a `email` como administrador, creando el usuario si no existe.

    Resuelve el huevo-y-gallina de una base recien creada: todos los accesos
    (Google o cuenta local) los aprueba un administrador, y en una base vacia
    no hay ninguno. Tambien sirve para sumar administradores sin tocar la
    base a mano. Idempotente: llamarlo dos veces no duplica nada. Si el
    correo tenia una solicitud de acceso Google pendiente, queda aprobada
    (el siguiente login con Google entra directo)."""

    email = email.strip()
    usuario = (
        db.query(models.Usuario)
        .filter(
            (func.lower(models.Usuario.email) == email.lower())
            | (func.lower(models.Usuario.email_google) == email.lower())
        )
        .first()
    )
    if usuario is None:
        usuario = models.Usuario(
            username=generar_username(email, db),
            email=email,
            email_google=email,
            nombre=nombre,
            activo=True,
        )
        db.add(usuario)
        db.flush()
    else:
        usuario.activo = True
        if nombre and not usuario.nombre:
            usuario.nombre = nombre
        if not usuario.email_google:
            usuario.email_google = email

    ya_admin = db.query(models.Administrador).filter(models.Administrador.usuario_id == usuario.id).first()
    # Designado a proposito en la app: el push de la web no se lo quita
    # aunque alla no sea administrador.
    if ya_admin is None:
        db.add(models.Administrador(usuario_id=usuario.id, origen="app"))
    else:
        ya_admin.origen = "app"

    solicitud = (
        db.query(models.SolicitudAccesoGoogle)
        .filter(func.lower(models.SolicitudAccesoGoogle.email) == email.lower())
        .first()
    )
    if solicitud is not None and solicitud.estado == "pendiente":
        solicitud.estado = "aprobada"

    db.commit()
    db.refresh(usuario)
    return usuario
