from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import distinct, func, tuple_
from sqlalchemy.orm import Session, aliased

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
    filas por id: eso mezcla corridas de distintos dias y trunca procesos.

    Se usa DISTINCT ON (especifico de Postgres) en vez de agrupar y despues
    hacer join contra la tabla completa de nuevo: con el indice en (nombre,
    fuente, snapshot_ts) esto resuelve en un solo recorrido, mientras que el
    group-by-y-join anterior escaneaba la tabla historica dos veces y con
    ella ya crecida superaba el statement_timeout de Postgres."""
    ultimo_por_proceso = (
        db.query(models.Control)
        .distinct(models.Control.nombre, models.Control.fuente)
        .order_by(
            models.Control.nombre,
            models.Control.fuente,
            models.Control.snapshot_ts.desc(),
        )
        .subquery()
    )
    UltimoControl = aliased(models.Control, ultimo_por_proceso)

    controles = (
        db.query(UltimoControl)
        .order_by(UltimoControl.nombre)
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
    # Cuenta (nombre, fuente) distintos por dia, no filas crudas: un mismo
    # proceso puede generar mas de una fila en rojo/naranja el mismo dia si
    # reintenta rapido y cambia de estado varias veces (ver comentario en
    # _actualizar_bitacora_proceso), lo que inflaba el conteo de "procesos
    # en falla" por dia.
    filas = (
        db.query(
            models.Control.snapshot_fecha,
            func.count(distinct(tuple_(models.Control.nombre, models.Control.fuente))).label("fallas"),
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
