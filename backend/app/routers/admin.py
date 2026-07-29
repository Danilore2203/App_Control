import re
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db

router = APIRouter(prefix="/admin", tags=["admin"])


def _generar_username(email: str, db: Session) -> str:
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


@router.get("/solicitudes", response_model=List[schemas.SolicitudAccesoOut])
def listar_solicitudes(
    estado: str = "pendiente",
    db: Session = Depends(get_db),
    _admin: models.Usuario = Depends(auth.requerir_admin),
):
    query = db.query(models.SolicitudAccesoGoogle)
    if estado != "todas":
        query = query.filter(models.SolicitudAccesoGoogle.estado == estado)
    return query.order_by(models.SolicitudAccesoGoogle.creado_en.desc()).all()


@router.post("/solicitudes/{solicitud_id}/aprobar", response_model=schemas.UsuarioOut)
def aprobar_solicitud(
    solicitud_id: int,
    db: Session = Depends(get_db),
    _admin: models.Usuario = Depends(auth.requerir_admin),
):
    solicitud = db.get(models.SolicitudAccesoGoogle, solicitud_id)
    if solicitud is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")

    usuario = db.query(models.Usuario).filter(models.Usuario.email.ilike(solicitud.email)).first()
    if usuario is None:
        usuario = models.Usuario(
            username=_generar_username(solicitud.email, db),
            email=solicitud.email,
            nombre=solicitud.nombre,
            activo=True,
        )
        db.add(usuario)

    usuario.activo = True
    solicitud.estado = "aprobada"
    db.commit()
    db.refresh(usuario)
    return usuario


@router.post("/solicitudes/{solicitud_id}/rechazar", response_model=schemas.SolicitudAccesoOut)
def rechazar_solicitud(
    solicitud_id: int,
    db: Session = Depends(get_db),
    _admin: models.Usuario = Depends(auth.requerir_admin),
):
    solicitud = db.get(models.SolicitudAccesoGoogle, solicitud_id)
    if solicitud is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")

    solicitud.estado = "rechazada"
    db.commit()
    db.refresh(solicitud)
    return solicitud


@router.get("/solicitudes-registro", response_model=List[schemas.SolicitudRegistroOut])
def listar_solicitudes_registro(
    estado: str = "pendiente",
    db: Session = Depends(get_db),
    _admin: models.Usuario = Depends(auth.requerir_admin),
):
    query = db.query(models.SolicitudRegistro)
    if estado != "todas":
        query = query.filter(models.SolicitudRegistro.estado == estado)
    return query.order_by(models.SolicitudRegistro.creado_en.desc()).all()


@router.post("/solicitudes-registro/{solicitud_id}/aprobar", response_model=schemas.UsuarioOut)
def aprobar_solicitud_registro(
    solicitud_id: int,
    db: Session = Depends(get_db),
    _admin: models.Usuario = Depends(auth.requerir_admin),
):
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


@router.post("/solicitudes-registro/{solicitud_id}/rechazar", response_model=schemas.SolicitudRegistroOut)
def rechazar_solicitud_registro(
    solicitud_id: int,
    db: Session = Depends(get_db),
    _admin: models.Usuario = Depends(auth.requerir_admin),
):
    solicitud = db.get(models.SolicitudRegistro, solicitud_id)
    if solicitud is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")

    solicitud.estado = "rechazada"
    db.commit()
    db.refresh(solicitud)
    return solicitud
