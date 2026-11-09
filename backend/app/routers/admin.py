from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db
from app.services.solicitudes import aprobar_solicitud_registro as _aprobar_solicitud_registro
from app.services.usuarios import generar_username

router = APIRouter(prefix="/admin", tags=["admin"])


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
    if solicitud.estado != "pendiente":
        # Sin este chequeo, dos aprobaciones casi simultaneas (doble click, o
        # dos admins) podian pasar juntas el "usuario is None" antes de que
        # la primera hiciera commit, e intentar crear dos Usuario para el
        # mismo email (no tiene unique=True), arriesgando una fila duplicada
        # o un IntegrityError en el username generado.
        raise HTTPException(status_code=400, detail="La solicitud ya fue procesada")

    usuario = db.query(models.Usuario).filter(func.lower(models.Usuario.email) == solicitud.email.strip().lower()).first()
    if usuario is None:
        usuario = models.Usuario(
            username=generar_username(solicitud.email, db),
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


@router.post("/usuarios/{usuario_id}/password", response_model=schemas.MensajeOut)
def asignar_password(
    usuario_id: int,
    payload: schemas.PasswordAdminIn,
    db: Session = Depends(get_db),
    _admin: models.Usuario = Depends(auth.requerir_admin),
):
    """Un administrador asigna (o resetea) la contrasena local de un usuario.
    Es la via para quien no tiene contrasena ni cuenta de Google: antes se
    podia "configurar" con solo escribir el correo de la cuenta, lo que
    permitia apropiarse de cualquier usuario."""
    usuario = db.get(models.Usuario, usuario_id)
    if usuario is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    usuario.password_hash = auth.hashear_password(payload.password)
    usuario.activo = True
    db.commit()
    return schemas.MensajeOut(ok=True, mensaje=f"Contrasena asignada a {usuario.username}")


@router.post("/solicitudes/{solicitud_id}/rechazar", response_model=schemas.SolicitudAccesoOut)
def rechazar_solicitud(
    solicitud_id: int,
    db: Session = Depends(get_db),
    _admin: models.Usuario = Depends(auth.requerir_admin),
):
    solicitud = db.get(models.SolicitudAccesoGoogle, solicitud_id)
    if solicitud is None:
        raise HTTPException(status_code=404, detail="Solicitud no encontrada")
    if solicitud.estado != "pendiente":
        # Rechazar una ya aprobada dejaba al usuario activo pero con la
        # solicitud en "rechazada": si despues se desactivaba, el login le
        # decia "fue rechazada" en vez de "pendiente".
        raise HTTPException(status_code=400, detail="La solicitud ya fue procesada")

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
    return _aprobar_solicitud_registro(db, solicitud_id)


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
