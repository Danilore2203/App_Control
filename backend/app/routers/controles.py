from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import distinct, func
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
        estado_ts=control.estado_ts,
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
    """Cantidad de procesos distintos que estuvieron en rojo/naranja cada
    dia, ultimos `dias` dias, para graficar la tendencia de fallas.

    El catalogo tiene UNA fila por proceso y dia que se actualiza en el
    lugar, asi que mirar solo el catalogo contaria unicamente los procesos
    que TERMINAN el dia en rojo (uno que fallo a las 8 y se arreglo a las 9
    no apareceria). Por eso se juntan dos fuentes: el estado del catalogo
    (cubre la primera carga del dia, que no genera eventos) y los eventos
    de cambio a rojo/naranja de dataops_catalogo_cambios."""
    colores = ["red", "orange"]
    rojos_catalogo = db.query(
        models.Control.snapshot_fecha.label("fecha"),
        models.Control.nombre.label("nombre"),
    ).filter(func.trim(func.lower(models.Control.color)).in_(colores))
    rojos_eventos = db.query(
        func.date(models.CatalogoCambio.ts).label("fecha"),
        models.CatalogoCambio.nombre.label("nombre"),
    ).filter(
        models.CatalogoCambio.tipo == "PROCESO",
        func.trim(func.lower(models.CatalogoCambio.color_nuevo)).in_(colores),
    )
    union = rojos_catalogo.union(rojos_eventos).subquery()
    filas = (
        db.query(union.c.fecha, func.count(distinct(union.c.nombre)).label("fallas"))
        .group_by(union.c.fecha)
        .order_by(union.c.fecha.desc())
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
