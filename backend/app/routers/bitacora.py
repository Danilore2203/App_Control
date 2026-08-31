from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends
from sqlalchemy import extract, func
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db
from app.services.poller import BOLIVIA_TZ

router = APIRouter(prefix="/bitacora", tags=["bitacora"])


@router.post("", response_model=schemas.BitacoraErrorOut)
def crear_entrada(
    payload: schemas.BitacoraErrorIn,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    entrada = models.BitacoraError(
        # El resto de la bitacora (generada por el poller) queda en hora
        # local Bolivia naive, tomada de snapshot_ts del origen. Si una
        # entrada manual no manda fecha_hora, el default debe seguir la
        # misma convencion -datetime.utcnow() quedaba 4h adelantada.
        fecha_hora=payload.fecha_hora or datetime.now(BOLIVIA_TZ).replace(tzinfo=None),
        nombre=payload.nombre.strip(),
        tecnologia=payload.tecnologia,
        estado=payload.estado,
        tipo=schemas.tipo_para_tecnologia(payload.tecnologia),
        descripcion=payload.descripcion.strip(),
        creado_por_id=usuario_actual.id,
    )
    db.add(entrada)
    db.commit()
    db.refresh(entrada)
    return entrada


@router.get("", response_model=List[schemas.BitacoraErrorOut])
def listar_entradas(
    anio: int,
    mes: Optional[int] = None,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    consulta = db.query(models.BitacoraError).filter(extract("year", models.BitacoraError.fecha_hora) == anio)
    if mes is not None:
        consulta = consulta.filter(extract("month", models.BitacoraError.fecha_hora) == mes)
    return consulta.order_by(models.BitacoraError.fecha_hora.desc()).all()


def _mismo_dia_anio_anterior(fecha: datetime) -> datetime:
    """fecha.replace(year=fecha.year - 1) explota con ValueError si fecha es
    29 de febrero de un anio bisiesto y el anterior no lo es. Cae a 28/2 en
    ese caso -un dia menos en la ventana de comparacion, aceptable para un
    numero comparativo YTD, contra un 500 seguro."""

    try:
        return fecha.replace(year=fecha.year - 1)
    except ValueError:
        return fecha.replace(year=fecha.year - 1, day=28)


def _contar_en_rango(db: Session, desde: datetime, hasta: datetime) -> int:
    return (
        db.query(func.count(models.BitacoraError.id))
        .filter(models.BitacoraError.fecha_hora >= desde, models.BitacoraError.fecha_hora <= hasta)
        .scalar()
        or 0
    )


@router.get("/resumen", response_model=schemas.BitacoraResumenAnioOut)
def resumen_anual(
    anio: int,
    db: Session = Depends(get_db),
    usuario_actual: models.Usuario = Depends(auth.obtener_usuario_actual),
):
    """Total por mes (para la grilla de 12 meses) + variacion vs el mismo
    periodo del anio anterior (para la tarjeta de resumen YTD)."""

    filas = (
        db.query(
            extract("month", models.BitacoraError.fecha_hora).label("mes"),
            func.count(models.BitacoraError.id).label("total"),
        )
        .filter(extract("year", models.BitacoraError.fecha_hora) == anio)
        .group_by("mes")
        .all()
    )
    totales_por_mes = {int(mes): int(total) for mes, total in filas}
    meses = [
        schemas.BitacoraResumenMesOut(
            mes=m, total=totales_por_mes.get(m, 0), tiene_error=totales_por_mes.get(m, 0) > 0
        )
        for m in range(1, 13)
    ]

    ahora = datetime.utcnow()
    es_anio_actual = anio == ahora.year
    hasta_actual = ahora if es_anio_actual else datetime(anio, 12, 31, 23, 59, 59)
    desde_actual = datetime(anio, 1, 1)
    total_anual = _contar_en_rango(db, desde_actual, hasta_actual)

    desde_anterior = datetime(anio - 1, 1, 1)
    hasta_anterior = _mismo_dia_anio_anterior(hasta_actual)
    total_anterior = _contar_en_rango(db, desde_anterior, hasta_anterior)

    variacion_pct = None
    if total_anterior > 0:
        variacion_pct = round((total_anual - total_anterior) / total_anterior * 100, 1)

    return schemas.BitacoraResumenAnioOut(
        anio=anio, total_anual=total_anual, variacion_pct=variacion_pct, meses=meses
    )
