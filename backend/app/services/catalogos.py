"""Recepcion de los catalogos que OP_PROD empuja por HTTPS.

Antes los catalogos llegaban por una replica MySQL -> Supabase que copiaba
tablas enteras cada minuto, y el poller de aca los sondeaba cada minuto para
descubrir que habia cambiado. Ahora OP_PROD, al terminar cada snapshot (cada
5 min), manda SOLO lo que cambio en ese ciclo:

  - `procesos` / `tablas`: filas a insertar-o-actualizar (upsert por id de
    MySQL, que desde el cambio de OP_PROD es estable durante todo el dia) y
    los ids que desaparecieron (`bajas`).
  - `eventos`: un registro por cada cambio de estado (id de
    c137.dataops_catalogo_cambios). Es lo que recorre el poller para la
    bitacora.
  - `completo=True`: el envio trae TODAS las filas del dia `fecha` (primera
    carga del dia, o resincronizacion despues de un fallo): las filas de ese
    dia que no vengan en el envio se eliminan.

Todo es idempotente: si OP_PROD reintenta el mismo envio (p.ej. porque se
le corto la red antes de recibir la respuesta), el resultado es el mismo.
"""
import logging
from typing import Iterable, Type

from sqlalchemy.orm import Session

from app import models, schemas

logger = logging.getLogger(__name__)


def _ids_referenciados_por_alertas(db: Session, ids: Iterable[int]) -> set[int]:
    """alertas.control_id tiene FK a dataops_catalogo_procesos: una fila de
    proceso que ya tiene alertas no se puede borrar sin romper la FK. Se
    deja (es historia del dia) y se informa como omitida."""
    ids = list(ids)
    if not ids:
        return set()
    filas = db.query(models.Alerta.control_id).filter(models.Alerta.control_id.in_(ids)).distinct().all()
    return {control_id for (control_id,) in filas}


def _aplicar_catalogo(
    db: Session,
    modelo: Type[models.Base],
    seccion: schemas.CatalogoProcesosIn | schemas.CatalogoTablasIn,
    fecha,
    completo: bool,
) -> schemas.CatalogoSeccionOut:
    columnas = {c.name for c in modelo.__table__.columns}
    ids_enviados = [fila.id for fila in seccion.upsert]

    existentes = {}
    if ids_enviados:
        existentes = {obj.id: obj for obj in db.query(modelo).filter(modelo.id.in_(ids_enviados)).all()}

    insertadas = actualizadas = 0
    for fila in seccion.upsert:
        datos = {k: v for k, v in fila.model_dump().items() if k in columnas}
        obj = existentes.get(fila.id)
        if obj is None:
            db.add(modelo(**datos))
            insertadas += 1
        else:
            for k, v in datos.items():
                setattr(obj, k, v)
            actualizadas += 1
    # Las filas nuevas tienen que estar en la base antes de calcular las
    # bajas del modo completo, si no se borrarian a si mismas.
    db.flush()

    a_borrar: set[int] = set(seccion.bajas)
    if completo:
        consulta = db.query(modelo.id).filter(modelo.snapshot_fecha == fecha)
        if ids_enviados:
            consulta = consulta.filter(modelo.id.notin_(ids_enviados))
        a_borrar.update(id_ for (id_,) in consulta.all())

    omitidas: set[int] = set()
    if a_borrar and modelo is models.Control:
        omitidas = _ids_referenciados_por_alertas(db, a_borrar)
        a_borrar -= omitidas

    eliminadas = 0
    if a_borrar:
        eliminadas = (
            db.query(modelo).filter(modelo.id.in_(list(a_borrar))).delete(synchronize_session=False)
        )

    return schemas.CatalogoSeccionOut(
        insertadas=insertadas,
        actualizadas=actualizadas,
        eliminadas=eliminadas,
        omitidas=len(omitidas),
    )


def _aplicar_eventos(db: Session, eventos: list[schemas.CatalogoEventoIn]) -> schemas.CatalogoEventosOut:
    if not eventos:
        return schemas.CatalogoEventosOut(insertados=0, ignorados=0)
    ids = [e.id for e in eventos]
    ya_estan = {id_ for (id_,) in db.query(models.CatalogoCambio.id).filter(models.CatalogoCambio.id.in_(ids)).all()}
    insertados = 0
    for evento in eventos:
        if evento.id in ya_estan:
            continue
        db.add(models.CatalogoCambio(**evento.model_dump()))
        ya_estan.add(evento.id)
        insertados += 1
    return schemas.CatalogoEventosOut(insertados=insertados, ignorados=len(eventos) - insertados)


def aplicar_push_catalogos(db: Session, push: schemas.CatalogoPushIn) -> schemas.CatalogoPushOut:
    """Aplica un envio de OP_PROD en una sola transaccion: o entra todo o no
    entra nada, para que un reintento parcial nunca deje los catalogos a
    medias respecto de los eventos."""
    try:
        procesos = _aplicar_catalogo(db, models.Control, push.procesos, push.fecha, push.completo)
        tablas = _aplicar_catalogo(db, models.Tabla, push.tablas, push.fecha, push.completo)
        eventos = _aplicar_eventos(db, push.eventos)
        db.commit()
    except Exception:
        db.rollback()
        raise

    resultado = schemas.CatalogoPushOut(procesos=procesos, tablas=tablas, eventos=eventos)
    logger.info(
        "Catalogos recibidos de OP_PROD (fecha %s, completo=%s): %s",
        push.fecha, push.completo, resultado.model_dump(),
    )
    return resultado
