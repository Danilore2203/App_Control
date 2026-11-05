from datetime import date, datetime

from app import models, schemas
from app.services.catalogos import aplicar_push_catalogos

HOY = date(2026, 11, 5)
AYER = date(2026, 11, 4)
TS = datetime(2026, 11, 5, 8, 0, 0)


def proceso(id_, nombre, estado="OK", color="green", fecha=HOY, ts=TS, **extra):
    return schemas.CatalogoProcesoIn(
        id=id_, nombre=nombre, fuente="AIRFLOW", estado=estado, color=color,
        snapshot_fecha=fecha, snapshot_ts=ts, estado_ts=ts, **extra,
    )


def tabla(id_, nombre, estado="OK", color="green", fecha=HOY, ts=TS):
    return schemas.CatalogoTablaIn(
        id=id_, nombre=nombre, fuente="QA_CONTROL", estado=estado, color=color,
        cantidad=10, snapshot_fecha=fecha, snapshot_ts=ts, estado_ts=ts,
    )


def evento(id_, nombre, anterior, nuevo, color="red", tipo="PROCESO", ts=TS):
    return schemas.CatalogoEventoIn(
        id=id_, tipo=tipo, nombre=nombre, fuente="AIRFLOW",
        estado_anterior=anterior, estado_nuevo=nuevo, color_nuevo=color, ts=ts,
    )


def push(fecha=HOY, completo=False, procesos=(), bajas_procesos=(), tablas=(), bajas_tablas=(), eventos=()):
    return schemas.CatalogoPushIn(
        fecha=fecha,
        completo=completo,
        procesos=schemas.CatalogoProcesosIn(upsert=list(procesos), bajas=list(bajas_procesos)),
        tablas=schemas.CatalogoTablasIn(upsert=list(tablas), bajas=list(bajas_tablas)),
        eventos=list(eventos),
    )


def test_primera_carga_inserta_todo(db):
    out = aplicar_push_catalogos(db, push(
        completo=True,
        procesos=[proceso(1, "carga_a"), proceso(2, "carga_b")],
        tablas=[tabla(10, "t_a")],
    ))

    assert out.procesos.model_dump() == {"insertadas": 2, "actualizadas": 0, "eliminadas": 0, "omitidas": 0}
    assert out.tablas.model_dump() == {"insertadas": 1, "actualizadas": 0, "eliminadas": 0, "omitidas": 0}
    assert out.eventos.model_dump() == {"insertados": 0, "ignorados": 0}
    assert db.query(models.Control).count() == 2
    assert db.query(models.Tabla).count() == 1


def test_reintento_del_mismo_envio_es_idempotente(db):
    envio = push(
        procesos=[proceso(1, "carga_a", estado="ERROR", color="red")],
        eventos=[evento(100, "carga_a", "OK", "ERROR")],
    )
    aplicar_push_catalogos(db, envio)
    out = aplicar_push_catalogos(db, envio)

    assert out.procesos.insertadas == 0 and out.procesos.actualizadas == 1
    assert out.eventos.model_dump() == {"insertados": 0, "ignorados": 1}
    assert db.query(models.Control).count() == 1
    assert db.query(models.CatalogoCambio).count() == 1


def test_cambio_incremental_actualiza_en_el_lugar_y_guarda_evento(db):
    aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "carga_a"), proceso(2, "carga_b")]))

    ts_error = datetime(2026, 11, 5, 8, 47, 0)
    out = aplicar_push_catalogos(db, push(
        procesos=[proceso(1, "carga_a", estado="ERROR", color="red", ts=ts_error)],
        eventos=[evento(100, "carga_a", "OK", "ERROR", ts=ts_error)],
    ))

    assert out.procesos.model_dump() == {"insertadas": 0, "actualizadas": 1, "eliminadas": 0, "omitidas": 0}
    fila = db.get(models.Control, 1)
    assert (fila.estado, fila.color, fila.estado_ts) == ("ERROR", "red", ts_error)
    # El otro proceso no se toco y el id sigue siendo el mismo.
    assert db.get(models.Control, 2).estado == "OK"
    assert db.query(models.Control).count() == 2
    cambio = db.get(models.CatalogoCambio, 100)
    assert (cambio.estado_anterior, cambio.estado_nuevo, cambio.ts) == ("OK", "ERROR", ts_error)


def test_bajas_borran_por_id(db):
    aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "a"), proceso(2, "b")], tablas=[tabla(10, "t")]))

    out = aplicar_push_catalogos(db, push(bajas_procesos=[2], bajas_tablas=[10]))

    assert out.procesos.eliminadas == 1 and out.tablas.eliminadas == 1
    assert [c.id for c in db.query(models.Control).all()] == [1]
    assert db.query(models.Tabla).count() == 0


def test_completo_elimina_lo_que_no_viene_solo_de_ese_dia(db):
    # Dia anterior intacto + filas de hoy "viejas" (p.ej. restos de la epoca
    # de la replica, con ids que ya no existen en MySQL).
    aplicar_push_catalogos(db, push(fecha=AYER, procesos=[proceso(90, "a", fecha=AYER)]))
    aplicar_push_catalogos(db, push(procesos=[proceso(1, "a"), proceso(2, "b"), proceso(3, "c")]))

    out = aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "a"), proceso(4, "d")]))

    assert out.procesos.model_dump() == {"insertadas": 1, "actualizadas": 1, "eliminadas": 2, "omitidas": 0}
    assert sorted(c.id for c in db.query(models.Control).all()) == [1, 4, 90]


def test_no_borra_un_proceso_que_tiene_alertas(db):
    aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "a"), proceso(2, "b")]))
    db.add(models.Alerta(control_id=2, mensaje="fallo", nivel="critica"))
    db.commit()

    out = aplicar_push_catalogos(db, push(bajas_procesos=[1, 2]))

    assert out.procesos.model_dump() == {"insertadas": 0, "actualizadas": 0, "eliminadas": 1, "omitidas": 1}
    assert [c.id for c in db.query(models.Control).all()] == [2]


def test_un_fallo_no_deja_el_envio_a_medias(db):
    aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "a")]))
    # Evento con nombre None viola NOT NULL al hacer flush: la transaccion
    # entera (incluida la actualizacion del proceso) debe deshacerse.
    envio = push(
        procesos=[proceso(1, "a", estado="ERROR", color="red")],
        eventos=[evento(100, "a", "OK", "ERROR")],
    )
    envio.eventos[0].nombre = None  # type: ignore[assignment]

    try:
        aplicar_push_catalogos(db, envio)
    except Exception:
        pass
    else:
        raise AssertionError("se esperaba que fallara")

    assert db.get(models.Control, 1).estado == "OK"
    assert db.query(models.CatalogoCambio).count() == 0
