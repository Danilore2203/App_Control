from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db

router = APIRouter(prefix="/alertas", tags=["alertas"])


@router.get("/infra", response_model=schemas.AlertasInfraOut)
def listar_alertas_infra(
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    """Alarmas de infraestructura (congestion en Netezza): las activas y el historial."""
    from app.services import alertas_infra

    return alertas_infra.listar(db)


@router.get("", response_model=List[schemas.AlertaOut])
def listar_alertas(
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    return (
        db.query(models.Alerta)
        .filter(models.Alerta.usuario_id == usuario_actual.id)
        .order_by(models.Alerta.creado_en.desc())
        .all()
    )
