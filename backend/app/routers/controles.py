from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db
from app.services.procesos import color_efectivo, estado_efectivo

router = APIRouter(prefix="/controles", tags=["controles"])


def _construir_control_out(control: models.Control) -> schemas.ControlOut:
    """Aplica la reclasificacion propia de la app (proceso core en DEMORADO
    que ya paso su hora_fin se muestra como ERROR) antes de exponerlo. No
    toca la fila real en dataops_catalogo_procesos, solo la respuesta."""
    return schemas.ControlOut(
        id=control.id,
        nombre=control.nombre,
        fuente=control.fuente,
        estado=estado_efectivo(control),
        color=color_efectivo(control),
        hora_programada=control.hora_programada,
        hora_log=control.hora_log,
        hora_fin=control.hora_fin,
        core=control.core,
        ruta=control.ruta,
        version=control.version,
        snapshot_fecha=control.snapshot_fecha,
        snapshot_ts=control.snapshot_ts,
    )


@router.get("", response_model=List[schemas.ControlOut])
def listar_controles(
    limit: int = 2000,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    """Estado actual de cada proceso en dataops_catalogo_procesos: un registro
    por (nombre, fuente), el de snapshot_ts mas reciente. La tabla guarda un
    historico de snapshots por dia, asi que no alcanza con tomar las ultimas N
    filas por id: eso mezcla corridas de distintos dias y trunca procesos."""
    ultimo_por_proceso = (
        db.query(
            models.Control.nombre,
            models.Control.fuente,
            func.max(models.Control.snapshot_ts).label("ultimo_ts"),
        )
        .group_by(models.Control.nombre, models.Control.fuente)
        .subquery()
    )

    controles = (
        db.query(models.Control)
        .join(
            ultimo_por_proceso,
            (models.Control.nombre == ultimo_por_proceso.c.nombre)
            & (models.Control.fuente == ultimo_por_proceso.c.fuente)
            & (models.Control.snapshot_ts == ultimo_por_proceso.c.ultimo_ts),
        )
        .order_by(models.Control.nombre)
        .limit(limit)
        .all()
    )
    return [_construir_control_out(c) for c in controles]


@router.get("/historial-fallas", response_model=List[schemas.HistorialFallaOut])
def historial_fallas(
    dias: int = 7,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    """Cantidad de procesos en rojo/naranja por dia, ultimos `dias` dias
    (segun snapshot_fecha), para graficar la tendencia de fallas reciente."""
    filas = (
        db.query(
            models.Control.snapshot_fecha,
            func.count(models.Control.id).label("fallas"),
        )
        .filter(func.trim(func.lower(models.Control.color)).in_(["red", "orange"]))
        .group_by(models.Control.snapshot_fecha)
        .order_by(models.Control.snapshot_fecha.desc())
        .limit(dias)
        .all()
    )
    return [
        schemas.HistorialFallaOut(fecha=fecha, fallas=fallas)
        for fecha, fallas in reversed(filas)
    ]


@router.get("/{control_id}", response_model=schemas.ControlOut)
def obtener_control(
    control_id: int,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    control = db.query(models.Control).filter(models.Control.id == control_id).first()
    if not control:
        raise HTTPException(status_code=404, detail="Proceso no encontrado")
    return _construir_control_out(control)
