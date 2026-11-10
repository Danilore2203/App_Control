"""GET /tablas: estado actual de las tablas del catalogo para la vista
Tablas del monitor (misma forma que /controles)."""
from datetime import date, datetime

from app import models
from app.routers.tablas import listar_tablas

HOY = date(2026, 11, 5)


def tabla(nombre, fuente, color, cantidad, **extra):
    return models.Tabla(
        nombre=nombre,
        fuente=fuente,
        estado="OK" if color == "green" else "VACÍA",
        color=color,
        cantidad=cantidad,
        snapshot_fecha=HOY,
        snapshot_ts=datetime(2026, 11, 5, 8, 0),
        **extra,
    )


def test_listar_tablas_devuelve_una_fila_por_tabla_con_sus_campos(db):
    db.add_all(
        [
            tabla("dwh.ventas", "PG_PROD", "green", 1200, layer="gold"),
            tabla("dwh.clientes", "PG_PROD", "red", 0, layer="silver"),
            tabla("FACT_LLAMADAS", "QA_CONTROL", "green", 55, hora_programada="06:00", ultima_fecha="2026-11-05 05:58"),
        ]
    )
    db.commit()

    filas = listar_tablas(db=db, usuario_actual=None)

    assert [f.nombre for f in filas] == ["FACT_LLAMADAS", "dwh.clientes", "dwh.ventas"]
    clientes = next(f for f in filas if f.nombre == "dwh.clientes")
    assert (clientes.color, clientes.estado, clientes.cantidad, clientes.layer) == ("red", "VACÍA", 0, "silver")
    fact = next(f for f in filas if f.nombre == "FACT_LLAMADAS")
    assert (fact.fuente, fact.hora_programada, fact.ultima_fecha) == ("QA_CONTROL", "06:00", "2026-11-05 05:58")


def test_la_marca_core_llega_del_push_y_sale_en_tablas(db):
    from app import schemas
    from app.services.catalogos import aplicar_push_catalogos

    def fila(id_, nombre, core=None):
        return {"id": id_, "nombre": nombre, "fuente": "QA_CONTROL", "estado": "OK", "color": "green", "cantidad": 5,
                "snapshot_fecha": HOY.isoformat(), "snapshot_ts": "2026-11-05T08:00:00", "core": core}

    aplicar_push_catalogos(db, schemas.CatalogoPushIn(**{
        "fecha": HOY.isoformat(), "completo": False,
        "tablas": {"upsert": [fila(1, "DW.DIM_PERSONA", "SI"), fila(2, "DW.OTRA")]},
    }))
    filas = {f.nombre: schemas.TablaOut.model_validate(f).core for f in listar_tablas(db=db, usuario_actual=None)}
    assert filas == {"DW.DIM_PERSONA": "SI", "DW.OTRA": None}

    # Un OP_PROD viejo manda la tabla sin «core»: la marca se conserva.
    sin_core = fila(1, "DW.DIM_PERSONA")
    del sin_core["core"]
    sin_core["estado"] = "ERROR"
    aplicar_push_catalogos(db, schemas.CatalogoPushIn(**{
        "fecha": HOY.isoformat(), "completo": False, "tablas": {"upsert": [sin_core]},
    }))
    persona = next(f for f in listar_tablas(db=db, usuario_actual=None) if f.nombre == "DW.DIM_PERSONA")
    assert (persona.estado, persona.core) == ("ERROR", "SI")
