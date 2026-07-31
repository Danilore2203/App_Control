import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from sqlalchemy import text

from app.database import Base, SessionLocal, engine
from app.rate_limit import limiter
from app.routers import admin as admin_router
from app.routers import alertas as alertas_router
from app.routers import auth as auth_router
from app.routers import bitacora as bitacora_router
from app.routers import controles as controles_router
from app.routers import infra as infra_router
from app.services.poller import (
    resincronizar_episodios_abiertos,
    revisar_alarmas_activas,
    revisar_procesos_nuevos,
    revisar_tablas_nuevas,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

Base.metadata.create_all(bind=engine)


def _migrar_columnas_legacy():
    """create_all() crea tablas nuevas pero NUNCA altera una que ya existe.
    La primera version de EpisodioAlerta tenia `push_ok` NOT NULL; se
    reemplazo por EpisodioAlertaUsuario (aviso por usuario, no por episodio
    entero) y el modelo actual ya no la escribe. Sin este parche, la
    columna vieja seguia ahi con esa restriccion y CADA intento de abrir un
    episodio de alarma NUEVO explotaba con NotNullViolation -la alarma
    nunca llegaba a dispararse, para ningun proceso nuevo en falla. Se
    corre una sola vez al arrancar, es idempotente: si la columna ya no
    existe, `IF EXISTS` no hace nada."""
    with engine.begin() as conn:
        try:
            conn.execute(text("ALTER TABLE episodios_alerta DROP COLUMN IF EXISTS push_ok"))
        except Exception:
            logger.exception("No se pudo correr la migracion de push_ok (revisar a mano si persiste)")


_migrar_columnas_legacy()


def _asegurar_indices():
    """create_all() no agrega indices nuevos a una tabla que ya existe.
    dataops_catalogo_procesos es una tabla historica (un snapshot por dia
    por proceso) que crecio lo suficiente como para que listar_controles
    -que agrupa por (nombre, fuente) buscando el ultimo snapshot_ts- empiece
    a superar el statement_timeout de Postgres por hacer seq scan. Se corre
    una sola vez al arrancar, es idempotente (`IF NOT EXISTS`)."""
    with engine.begin() as conn:
        try:
            conn.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS "
                    "ix_dataops_catalogo_procesos_nombre_fuente_snapshot_ts "
                    "ON dataops_catalogo_procesos (nombre, fuente, snapshot_ts)"
                )
            )
        except Exception:
            logger.exception("No se pudo crear el indice de dataops_catalogo_procesos")


_asegurar_indices()

INTERVALO_POLLER_SEGUNDOS = 60


def _ejecutar_poller():
    db = SessionLocal()
    try:
        # Va primero y no depende de las otras dos: decide la alarma mirando
        # el estado ACTUAL de cada proceso, no filas nuevas ni el cursor de
        # bitacora, para que una falla en esas otras dos nunca le cueste una
        # alarma real al usuario.
        revisar_alarmas_activas(db)
        revisar_procesos_nuevos(db)
        revisar_tablas_nuevas(db)
        resincronizar_episodios_abiertos(db)
    finally:
        db.close()


async def _loop_poller():
    while True:
        try:
            await asyncio.to_thread(_ejecutar_poller)
        except Exception:
            logger.exception("El poller fallo en este ciclo, reintenta en %ss", INTERVALO_POLLER_SEGUNDOS)
        await asyncio.sleep(INTERVALO_POLLER_SEGUNDOS)


@asynccontextmanager
async def lifespan(app: FastAPI):
    tarea_poller = asyncio.create_task(_loop_poller())
    yield
    tarea_poller.cancel()


app = FastAPI(title="API Controles", lifespan=lifespan)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    # La app movil (Android nativo) no esta sujeta a CORS -esto solo importa
    # para cuando se prueba con `flutter run -d chrome`. Si algun dia hay un
    # panel/monitor web real que llame esta API, agregar su dominio aca.
    allow_origin_regex=r"^https?://localhost(:\d+)?$",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router.router)
app.include_router(controles_router.router)
app.include_router(alertas_router.router)
app.include_router(admin_router.router)
app.include_router(infra_router.router)
app.include_router(bitacora_router.router)


@app.get("/health")
def health():
    return {"status": "ok"}
