from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from app.config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True, connect_args={"connect_timeout": 10})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
# Sesion del ciclo del poller: commitea fila por fila (para que un dato roto
# no se lleve puesto el lote) y, con expire_on_commit (el default), cada
# commit vencia TODOS los objetos ya cargados -tocar el siguiente proceso de
# la lista disparaba un SELECT nuevo. Con ~2.600 procesos eso eran miles de
# consultas por ciclo que no aportaban nada: lo que esta en memoria es
# exactamente lo que se acaba de commitear.
PollerSessionLocal = sessionmaker(autocommit=False, autoflush=False, expire_on_commit=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
