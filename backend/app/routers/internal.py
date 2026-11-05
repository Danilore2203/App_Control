from datetime import date, datetime

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app import auth, schemas
from app.database import get_db
from app.services.catalogos import aplicar_push_catalogos, estado_catalogos
from app.services.ciclo import ejecutar_ciclo_en_segundo_plano
from app.services.poller import BOLIVIA_TZ
from app.services.solicitudes import aprobar_solicitud_registro
from app.services.usuarios import designar_administrador

router = APIRouter(prefix="/internal", tags=["internal"])


@router.post(
    "/catalogos",
    response_model=schemas.CatalogoPushOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def recibir_catalogos(push: schemas.CatalogoPushIn, db: Session = Depends(get_db)):
    """Punto de entrada de los catalogos: OP_PROD lo llama al final de cada
    snapshot con lo que cambio en ese ciclo (ver app/services/catalogos.py
    para el contrato). Reemplaza a la replica MySQL -> Supabase y al sondeo
    del poller sobre los catalogos.

    Apenas queda aplicado se dispara un ciclo del poller en segundo plano
    (alarmas, bitacora) y, si el envio trajo algo, el aviso silencioso a
    los celulares para que refresquen: asi la app se entera en el mismo
    minuto en que OP_PROD vio el cambio, sin sondear."""
    resultado = aplicar_push_catalogos(db, push)
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


@router.get(
    "/catalogos/estado",
    response_model=schemas.CatalogoEstadoOut,
    dependencies=[Depends(auth.verificar_internal_key)],
)
def estado_catalogos_interno(fecha: date | None = None, db: Session = Depends(get_db)):
    """Que hay en la base para un dia (hoy por defecto, hora Bolivia): para
    contrastar con MySQL de OP_PROD y ver si el push esta llegando."""
    return estado_catalogos(db, fecha or datetime.now(BOLIVIA_TZ).date())


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
