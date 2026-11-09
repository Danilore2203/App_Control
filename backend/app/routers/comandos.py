from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db
from app.services import comandos as servicio

router = APIRouter(prefix="/comandos", tags=["comandos"])


@router.post("", response_model=schemas.ComandoOut)
def crear(
    pedido: schemas.ComandoIn,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    """Deja un comando para que OP_PROD lo ejecute adentro de la red (ver
    services/comandos.py). Las acciones exigen administrador."""
    return servicio.crear_comando(db, usuario_actual, pedido)


@router.get("/{comando_id}", response_model=schemas.ComandoOut)
def obtener(
    comando_id: int,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    return servicio.obtener_comando(db, comando_id, usuario_actual)


@router.get("", response_model=List[schemas.ComandoOut])
def recientes(
    limite: int = 50,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.requerir_admin),
):
    """Ultimos comandos: quien pidio que y como termino."""
    return servicio.listar_recientes(db, min(limite, 200))
