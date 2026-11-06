from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session, aliased

from app import auth, models, schemas
from app.database import get_db

router = APIRouter(prefix="/tablas", tags=["tablas"])


@router.get("", response_model=List[schemas.TablaOut])
def listar_tablas(
    limit: int = 10000,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    """Estado actual de cada tabla en dataops_catalogo_tablas: un registro por
    (nombre, fuente), el de snapshot_ts mas reciente. Mismo criterio que
    /controles (DISTINCT ON de Postgres sobre el indice nombre/fuente/
    snapshot_ts), sin reclasificacion: las tablas no tienen DEMORADO."""
    ultima_por_tabla = (
        db.query(models.Tabla)
        .distinct(models.Tabla.nombre, models.Tabla.fuente)
        .order_by(
            models.Tabla.nombre,
            models.Tabla.fuente,
            models.Tabla.snapshot_ts.desc(),
        )
        .subquery()
    )
    UltimaTabla = aliased(models.Tabla, ultima_por_tabla)

    return (
        db.query(UltimaTabla)
        .order_by(UltimaTabla.nombre)
        .limit(limit)
        .all()
    )
