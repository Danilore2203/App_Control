"""Poller sobre los eventos de cambio (incoherencia proceso/tabla, cursor),
resincronizacion de episodios propios, purga diaria y grafico de fallas.
Los episodios de proceso/tabla ya no los genera el poller: vienen de MySQL."""
from datetime import date, datetime, timedelta

from app import models
from app.routers.controles import historial_fallas
from app.services import poller

HOY = date(2026, 11, 5)
T_CARGA = datetime(2026, 11, 5, 0, 31)
T_ERROR = datetime(2026, 11, 5, 8, 47)
T_OK = datetime(2026, 11, 5, 9, 3)


def control(db, id_, nombre, estado="OK", color="green", core="NO", fecha=HOY, ts=T_CARGA):
    fila = models.Control(
        id=id_, nombre=nombre, fuente="AIRFLOW", estado=estado, color=color, core=core,
        snapshot_fecha=fecha, snapshot_ts=ts, estado_ts=ts,
    )
    db.add(fila)
    db.commit()
    return fila


def tabla(db, id_, nombre, estado="OK", color="green", cantidad=10, fecha=HOY, ts=T_CARGA):
    fila = models.Tabla(
        id=id_, nombre=nombre, fuente="QA_CONTROL", estado=estado, color=color, cantidad=cantidad,
        snapshot_fecha=fecha, snapshot_ts=ts, estado_ts=ts,
    )
    db.add(fila)
    db.commit()
    return fila


def evento(db, id_, nombre, anterior, nuevo, color, ts, tipo="PROCESO", fuente="AIRFLOW"):
    ev = models.CatalogoCambio(
        id=id_, tipo=tipo, nombre=nombre, fuente=fuente, estado_anterior=anterior,
        estado_nuevo=nuevo, color_nuevo=color, ts=ts,
    )
    db.add(ev)
    db.commit()
    return ev


def bitacora(db):
    return db.query(models.BitacoraError).order_by(models.BitacoraError.id).all()


def test_los_eventos_no_generan_episodios_de_bitacora_pero_avanzan_el_cursor(db):
    control(db, 1, "carga_a", estado="ERROR", color="red", ts=T_ERROR)
    evento(db, 100, "carga_a", "OK", "ERROR", "red", T_ERROR)
    evento(db, 101, "carga_a", "ERROR", "OK", "green", T_OK)

    assert poller.revisar_cambios_nuevos(db) == 2

    assert bitacora(db) == []  # los episodios de proceso vienen replicados de MySQL
    assert db.query(models.PollerState).one().ultimo_cambio_revisado == 101
    assert poller.revisar_cambios_nuevos(db) == 0


def test_proceso_core_ok_con_tabla_en_rojo_abre_incoherencia(db):
    control(db, 1, "carga_core", estado="OK", color="green", core="SI", ts=T_OK)
    tabla(db, 10, "t_ventas", estado="VACIA", color="red", cantidad=0, ts=T_OK)
    db.add(models.ProcesoTabla(proceso_nombre="carga_core", tabla_nombre="t_ventas", tipo_relacion="ALIMENTA", activo=True))
    db.commit()
    evento(db, 100, "carga_core", "ERROR", "OK", "green", T_OK)

    poller.revisar_cambios_nuevos(db)

    (ep,) = bitacora(db)
    assert (ep.nombre, ep.estado, ep.estado_fin, ep.origen_id) == ("carga_core -> t_ventas", "INCOHERENCIA", "ERROR", None)
    assert ep.fecha_hora == T_OK


def test_resincronizar_solo_toca_episodios_propios(db):
    # Episodio replicado de MySQL (origen_id): aunque el proceso ya este en
    # verde, lo cierra OP_PROD alla, no la app.
    db.add(models.BitacoraError(origen_id=7, fecha_hora=T_ERROR, nombre="carga_a", tecnologia="AIRFLOW",
                                descripcion="x", estado="ERROR", estado_fin="ERROR", tipo="PROCESO"))
    # Incoherencia propia, ya resuelta en el catalogo: esta si se cierra.
    db.add(models.BitacoraError(fecha_hora=T_ERROR, nombre="carga_core -> t", tecnologia="AIRFLOW",
                                descripcion="inc", estado="INCOHERENCIA", estado_fin="ERROR", tipo="PROCESO"))
    db.commit()
    control(db, 1, "carga_a", estado="OK", color="green", ts=T_OK)

    poller.resincronizar_episodios_abiertos(db)

    replicado, propio = bitacora(db)
    assert replicado.estado_fin == "ERROR"
    assert propio.estado_fin == "ERROR"  # no hay fila de catalogo para "carga_core -> t": queda igual


def test_alarma_usa_la_hora_del_cambio_de_estado(db):
    fila = models.Control(
        id=1, nombre="core_a", fuente="AIRFLOW", estado="ERROR", color="red", core="SI",
        snapshot_fecha=HOY, snapshot_ts=T_OK, estado_ts=T_ERROR,
    )
    db.add(fila)
    db.commit()

    poller._revisar_alarma_de_proceso(db, fila)  # sin destinatarios: no manda push, pero abre el episodio
    db.commit()

    ep = db.query(models.EpisodioAlerta).one()
    assert ep.abierto and ep.primera_deteccion == T_ERROR


def test_purga_borra_lo_viejo_y_respeta_las_alertas(db):
    poller._ultima_purga = None
    viejo = HOY - timedelta(days=90)
    control(db, 1, "viejo", fecha=viejo, ts=datetime.combine(viejo, datetime.min.time()))
    control(db, 2, "viejo_con_alerta", fecha=viejo, ts=datetime.combine(viejo, datetime.min.time()))
    control(db, 3, "reciente")
    tabla(db, 10, "t_vieja", fecha=viejo, ts=datetime.combine(viejo, datetime.min.time()))
    evento(db, 100, "viejo", "OK", "ERROR", "red", datetime.combine(HOY - timedelta(days=200), datetime.min.time()))
    evento(db, 101, "reciente", "OK", "ERROR", "red", T_ERROR)
    db.add(models.Alerta(control_id=2, mensaje="x", nivel="critica", creado_en=T_ERROR))
    db.add(models.BitacoraError(origen_id=1, fecha_hora=datetime.combine(HOY - timedelta(days=400), datetime.min.time()),
                                nombre="muy_viejo", tecnologia="AIRFLOW", descripcion="x", estado_fin="OK", tipo="PROCESO"))
    db.add(models.BitacoraError(origen_id=2, fecha_hora=datetime.combine(HOY - timedelta(days=300), datetime.min.time()),
                                nombre="dentro_del_anio", tecnologia="AIRFLOW", descripcion="x", estado_fin="OK", tipo="PROCESO"))
    db.commit()

    borrado = poller.purgar_historial(db, hoy=HOY)

    assert borrado == {"bitacora": 1, "alertas": 0, "procesos": 1, "tablas": 1, "eventos": 1}
    assert sorted(c.id for c in db.query(models.Control).all()) == [2, 3]
    assert [b.nombre for b in bitacora(db)] == ["dentro_del_anio"]
    assert poller.purgar_historial(db, hoy=HOY) == {}  # una vez por dia


def test_historial_fallas_cuenta_procesos_que_fallaron_aunque_se_hayan_recuperado(db):
    ayer = HOY - timedelta(days=1)
    control(db, 1, "a", estado="OK", color="green")              # fallo hoy pero ya esta OK (evento)
    control(db, 2, "b", estado="ERROR", color="red")             # sigue en rojo (catalogo)
    control(db, 3, "c", estado="OK", color="green")              # nunca fallo
    control(db, 4, "a", estado="ERROR", color="red", fecha=ayer)  # ayer termino en rojo
    evento(db, 100, "a", "OK", "ERROR", "red", T_ERROR)
    evento(db, 101, "b", "OK", "ERROR", "red", T_ERROR)          # mismo proceso que el catalogo: no duplica

    filas = historial_fallas(dias=7, db=db, usuario_actual=None)

    assert [(f.fecha, f.fallas) for f in filas] == [(ayer, 1), (HOY, 2)]
