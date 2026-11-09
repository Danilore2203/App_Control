"""/controles muestra los DAGs pausados por su ultima corrida (como el Monitor
Airflow) cuando esa informacion llego hace poco."""
from datetime import date, datetime, timedelta

from app import models
from app.routers.controles import listar_controles

HOY = date(2026, 11, 9)
TS = datetime(2026, 11, 9, 10, 0)


def dag(nombre, estado, color):
    return models.Control(nombre=nombre, fuente="AIRFLOW", estado=estado, color=color,
                          snapshot_fecha=HOY, snapshot_ts=TS, estado_ts=TS)


def estado(dag_id, last_state, hace_minutos=1, paused=True):
    return models.AirflowEstado(dag_id=dag_id, last_state=last_state, is_paused=paused,
                                actualizado_en=datetime.utcnow() - timedelta(minutes=hace_minutos))


def _por_nombre(db):
    return {c.nombre: (c.color, c.estado) for c in listar_controles(db=db, usuario_actual=None)}


def test_un_pausado_con_ultima_corrida_ok_se_muestra_ok(db):
    db.add_all([dag("a", "PAUSADO", "gray"), dag("b", "PAUSADO", "gray"), dag("c", "PAUSADO", "gray"),
                dag("d", "ERROR", "red"), dag("e", "SIN EJECUCIÓN", "gray")])
    db.add_all([estado("a", "success"), estado("b", "failed"), estado("c", None), estado("d", "success")])
    db.commit()

    assert _por_nombre(db) == {
        "a": ("green", "OK"),          # pausado pero su ultima corrida fue OK
        "b": ("red", "ERROR"),
        "c": ("gray", "PAUSADO"),      # sin corrida que lo clasifique
        "d": ("red", "ERROR"),         # no estaba en gris: el catalogo manda
        "e": ("gray", "SIN EJECUCIÓN"),  # sin informacion del monitor
    }


def test_si_la_informacion_es_vieja_se_vuelve_al_catalogo(db):
    db.add(dag("a", "PAUSADO", "gray"))
    db.add(estado("a", "success", hace_minutos=45))
    db.commit()
    assert _por_nombre(db) == {"a": ("gray", "PAUSADO")}
