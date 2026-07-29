import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.database import Base, SessionLocal, engine
from app.rate_limit import limiter
from app.routers import admin as admin_router
from app.routers import alertas as alertas_router
from app.routers import auth as auth_router
from app.routers import bitacora as bitacora_router
from app.routers import controles as controles_router
from app.routers import infra as infra_router
from app.services.poller import revisar_procesos_nuevos, revisar_tablas_nuevas

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

Base.metadata.create_all(bind=engine)

INTERVALO_POLLER_SEGUNDOS = 60


def _ejecutar_poller():
    db = SessionLocal()
    try:
        revisar_procesos_nuevos(db)
        revisar_tablas_nuevas(db)
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
