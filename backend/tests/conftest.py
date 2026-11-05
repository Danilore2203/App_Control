"""Fixtures compartidas. Las pruebas no tocan la base real: cada una corre
contra una SQLite en memoria con el mismo esquema de los modelos."""
import os

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# app.database crea el engine al importarse leyendo Settings(); sin estas
# variables la importacion explota antes de llegar a cualquier prueba.
os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("JWT_SECRET", "secreto-de-pruebas")

from app.database import Base  # noqa: E402
from app import models  # noqa: E402,F401  (registra las tablas en Base)


@pytest.fixture
def db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    sesion = Session()
    try:
        yield sesion
    finally:
        sesion.close()
        engine.dispose()
