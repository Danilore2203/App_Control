import logging
from datetime import date, datetime

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app import auth, models, schemas
from app.database import get_db
from app.services.catalogos import aplicar_push_catalogos, eliminar_bitacora_local_automatica, estado_catalogos
from app.services.ciclo import ejecutar_ciclo_en_segundo_plano
from app.services.poller import BOLIVIA_TZ
from app.services.solicitudes import aprobar_solicitud_registro
from app.services.usuarios import designar_administrador

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/internal", tags=["internal"])

# Ultimos envios recibidos (en memoria del proceso): de que IP vinieron y
# que trajeron. Para saber quien manda cuando llega un envio raro (el
# 9/11 un "completo" a medias vacio la app y no habia forma de saber de
# donde salio). Se ve en GET /internal/catalogos/estado.
_ultimos_envios: list[dict] = []


def _registrar_envio(request: Request, push: schemas.CatalogoPushIn, resultado: schemas.CatalogoPushOut) -> None:
    origen = request.headers.get("x-forwarded-for") or (request.client.host if request.client else "?")
    registro = {
        "ts": datetime.now(BOLIVIA_TZ).replace(tzinfo=None).isoformat(timespec="seconds"),
        "desde": origen,
        "completo": push.completo,
        "procesos": len(push.procesos.upsert),
        "tablas": len(push.tablas.upsert),
        "bitacora": len(push.bitacora.upsert) if push.bitacora else None,
        "vigentes": len(push.bitacora.vigentes.ids) if push.bitacora and push.bitacora.vigentes else None,
        "resultado": resultado.model_dump(exclude_none=True),
    }
    logger.info("push de catalogos: %s", registro)
    _ultimos_envios.append(registro)
    del _ultimos_envios[:-10]


@router.post(
    "/catalogos",
    response_model=schemas.CatalogoPushOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def recibir_catalogos(push: schemas.CatalogoPushIn, request: Request, db: Session = Depends(get_db)):
    """Punto de entrada de los catalogos: OP_PROD lo llama al final de cada
    snapshot con lo que cambio en ese ciclo (ver app/services/catalogos.py
    para el contrato). Reemplaza a la replica MySQL -> Supabase y al sondeo
    del poller sobre los catalogos.

    Apenas queda aplicado se dispara un ciclo del poller en segundo plano
    (alarmas, bitacora) y, si el envio trajo algo, el aviso silencioso a
    los celulares para que refresquen: asi la app se entera en el mismo
    minuto en que OP_PROD vio el cambio, sin sondear."""
    resultado = aplicar_push_catalogos(db, push)
    _registrar_envio(request, push, resultado)
    hubo_cambios = any(
        v for seccion in (resultado.procesos, resultado.tablas) for v in seccion.model_dump().values()
    ) or resultado.eventos.insertados > 0
    ejecutar_ciclo_en_segundo_plano(avisar_app=hubo_cambios)
    return resultado


@router.post(
    "/administradores",
    response_model=schemas.UsuarioOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def designar_administrador_interno(datos: schemas.AdministradorIn, db: Session = Depends(get_db)):
    """Deja a un correo como administrador, creando el usuario si no existe.
    Es la unica forma de tener el PRIMER administrador en una base nueva
    (todos los demas accesos los aprueba un administrador). Idempotente."""
    usuario = designar_administrador(db, datos.email, datos.nombre)
    return schemas.UsuarioOut.model_validate(usuario, from_attributes=True).model_copy(update={"es_admin": True})


@router.delete(
    "/bitacora/locales-automaticas",
    response_model=schemas.MensajeOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def borrar_bitacora_local_automatica(db: Session = Depends(get_db)):
    """Limpieza unica: borra los episodios que el poller viejo de la app
    genero por su cuenta (duplican a los replicados de MySQL). Conserva
    entradas manuales e incoherencias."""
    borradas = eliminar_bitacora_local_automatica(db)
    return schemas.MensajeOut(ok=True, mensaje=f"{borradas} episodios locales automaticos eliminados")


@router.get(
    "/catalogos/estado",
    response_model=schemas.CatalogoEstadoOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def estado_catalogos_interno(fecha: date | None = None, db: Session = Depends(get_db)):
    """Que hay en la base para un dia (hoy por defecto, hora Bolivia): para
    contrastar con MySQL de OP_PROD y ver si el push esta llegando."""
    estado = estado_catalogos(db, fecha or datetime.now(BOLIVIA_TZ).date())
    estado.ultimos_envios = list(reversed(_ultimos_envios))
    return estado


@router.post(
    "/solicitudes-registro/{solicitud_id}/aprobar",
    response_model=schemas.UsuarioOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def aprobar_solicitud_registro_interno(solicitud_id: int, db: Session = Depends(get_db)):
    """Igual que /admin/solicitudes-registro/{id}/aprobar, pero pensado para
    que lo llame el backend de op_prod (server-a-server, con clave interna en
    vez de un JWT de admin humano) cuando resuelve la solicitud reflejada en
    su propio panel de Usuarios."""
    return aprobar_solicitud_registro(db, solicitud_id)


@router.post(
    "/airflow/estados",
    response_model=schemas.AirflowEstadosOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def recibir_estados_airflow(payload: schemas.AirflowEstadosIn, db: Session = Depends(get_db)):
    """Ultima corrida de cada DAG segun el Monitor Airflow de OP (ver
    models.AirflowEstado). Reemplaza la lista completa."""
    ahora = datetime.utcnow()
    db.query(models.AirflowEstado).delete(synchronize_session=False)
    for e in payload.estados:
        db.add(models.AirflowEstado(dag_id=e.dag_id, last_state=e.last_state, is_paused=e.is_paused, actualizado_en=ahora))
    db.commit()
    return schemas.AirflowEstadosOut(recibidos=len(payload.estados), actualizado_en=ahora)
