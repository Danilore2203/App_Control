from fastapi import HTTPException
from sqlalchemy.orm import Session

from app import models


def aprobar_solicitud_registro(db: Session, solicitud_id: int) -> models.Usuario:
    """Crea la cuenta a partir de una solicitud de registro pendiente, con el
    password_hash que ya se guardo en la solicitud (nunca se recibe en texto
    plano aca). Usado tanto por el panel de admin propio como por op_prod al
    aprobar la solicitud reflejada en su panel de Usuarios."""
    solicitud = db.get(models.SolicitudRegistro, solicitud_id)
    if solicitud is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if solicitud.estado != "pendiente":
        raise HTTPException(status_code=400, detail="Esta solicitud ya fue resuelta")

    existente = db.query(models.Usuario).filter(models.Usuario.username == solicitud.username).first()
    if existente:
        raise HTTPException(status_code=400, detail="Ya existe un usuario con ese nombre de usuario")

    usuario = models.Usuario(
        username=solicitud.username,
        email=solicitud.email,
        nombre=solicitud.nombre,
        password_hash=solicitud.password_hash,
        activo=True,
    )
    db.add(usuario)
    solicitud.estado = "aprobada"
    db.commit()
    db.refresh(usuario)
    return usuario
