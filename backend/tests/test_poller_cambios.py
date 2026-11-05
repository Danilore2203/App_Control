"""Bitacora a partir de los eventos de cambio de estado (revisar_cambios_nuevos),
purga diaria y grafico de fallas, sin Postgres ni Firebase."""
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


def test_evento_de_error_abre_episodio_con_la_hora_real(db):
    control(db, 1, "carga_a", estado="ERROR", color="red", ts=T_ERROR)
    evento(db, 100, "carga_a", "OK", "ERROR", "red", T_ERROR)

    assert poller.revisar_cambios_nuevos(db) == 1

    (ep,) = bitacora(db)
    assert (ep.nombre, ep.tecnologia, ep.tipo, ep.estado, ep.estado_fin) == ("carga_a", "AIRFLOW", "PROCESO", "ERROR", "ERROR")
    assert ep.fecha_hora == T_ERROR
    assert "a las 08:47" in ep.descripcion
    assert db.query(models.PollerState).one().ultimo_cambio_revisado == 100


def test_dos_eventos_del_mismo_proceso_en_un_ciclo_se_ven_los_dos(db):
    # Entre un ciclo y otro el proceso fallo y se recupero: la fila de
    # catalogo ya esta en OK, pero la bitacora tiene que registrar el
    # episodio completo, con las dos horas.
    control(db, 1, "carga_a", estado="OK", color="green", ts=T_OK)
    evento(db, 100, "carga_a", "OK", "ERROR", "red", T_ERROR)
    evento(db, 101, "carga_a", "ERROR", "OK", "green", T_OK)

    assert poller.revisar_cambios_nuevos(db) == 2

    (ep,) = bitacora(db)
    assert ep.estado_fin == "OK"
    assert ep.fecha_hora == T_ERROR and ep.fecha_actualizacion == T_OK
    assert "a las 08:47" in ep.descripcion and "Solucionado - Estado OK a las 09:03" in ep.descripcion
    assert "Duración: 16m" in ep.descripcion


def test_demorado_se_registra_como_tal(db):
    control(db, 1, "carga_a", estado="EN EJECUCION", color="orange", ts=T_ERROR)
    evento(db, 100, "carga_a", "EN EJECUCION", "EN EJECUCION", "orange", T_ERROR)

    poller.revisar_cambios_nuevos(db)

    (ep,) = bitacora(db)
    assert ep.estado == "DEMORADO"
    assert "demorado a las 08:47" in ep.descripcion


def test_evento_de_tabla_vacia(db):
    tabla(db, 10, "t_ventas", estado="VACIA", color="red", cantidad=0, ts=T_ERROR)
    evento(db, 100, "t_ventas", "OK", "VACIA", "red", T_ERROR, tipo="TABLA", fuente="QA_CONTROL")

    poller.revisar_cambios_nuevos(db)

    (ep,) = bitacora(db)
    assert (ep.tipo, ep.tecnologia, ep.estado) == ("TABLA", "QA_CONTROL", "VACIA")
    assert "(cantidad=0)" in ep.descripcion


def test_evento_sin_fila_de_catalogo_no_rompe_el_ciclo(db):
    # Baja a mitad del dia: la fila ya no esta, pero el evento se registra igual.
    evento(db, 100, "carga_x", "OK", "ERROR", "red", T_ERROR)
    control(db, 2, "carga_b", estado="ERROR", color="red", ts=T_ERROR)
    evento(db, 101, "carga_b", "OK", "ERROR", "red", T_ERROR)

    assert poller.revisar_cambios_nuevos(db) == 2
    assert [e.nombre for e in bitacora(db)] == ["carga_x", "carga_b"]


def test_cursor_no_reprocesa_eventos_ya_vistos(db):
    control(db, 1, "carga_a", estado="ERROR", color="red", ts=T_ERROR)
    evento(db, 100, "carga_a", "OK", "ERROR", "red", T_ERROR)
    poller.revisar_cambios_nuevos(db)

    assert poller.revisar_cambios_nuevos(db) == 0
    assert len(bitacora(db)) == 1


def test_alarma_usa_la_hora_del_cambio_de_estado(db):
    # Fila cuyo snapshot_ts es posterior al cambio de estado (cambio hora_log
    # despues): la alarma debe quedar con estado_ts, no con snapshot_ts.
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
    db.commit()

    borrado = poller.purgar_historial(db, hoy=HOY)

    assert borrado == {"alertas": 0, "procesos": 1, "tablas": 1, "eventos": 1}
    assert sorted(c.id for c in db.query(models.Control).all()) == [2, 3]
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
