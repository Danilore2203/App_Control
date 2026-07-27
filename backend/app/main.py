import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import Base, SessionLocal, engine
from app.routers import admin as admin_router
from app.routers import alertas as alertas_router
from app.routers import auth as auth_router
from app.routers import bitacora as bitacora_router
from app.routers import controles as controles_router
from app.routers import infra as infra_router
from app.services.poller import revisar_procesos_nuevos, revisar_tablas_nuevas

Base.metadata.create_all(bind=engine)

INTERVALO_POLLER_SEGUNDOS = 60


async def _loop_poller():
    while True:
        try:
            db = SessionLocal()
            try:
                revisar_procesos_nuevos(db)
                revisar_tablas_nuevas(db)
            finally:
                db.close()
        except Exception:
            pass
        await asyncio.sleep(INTERVALO_POLLER_SEGUNDOS)


@asynccontextmanager
async def lifespan(app: FastAPI):
    tarea_poller = asyncio.create_task(_loop_poller())
    yield
    tarea_poller.cancel()


app = FastAPI(title="API Controles", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_credentials=True,
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
