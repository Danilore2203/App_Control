from datetime import datetime, timedelta

from app import models
from app.routers.bitacora import resumen_anual
from app.services.poller import BOLIVIA_TZ


def entrada(db, fecha_hora, estado_fin="OK", origen_id=None):
    db.add(models.BitacoraError(
        origen_id=origen_id, fecha_hora=fecha_hora, nombre="p", tecnologia="AIRFLOW", descripcion="x",
        estado="ERROR", estado_fin=estado_fin, tipo="PROCESO",
    ))
    db.commit()


def test_resumen_trae_abiertos_por_mes_y_los_indicadores_del_momento(db):
    ahora = datetime.now(BOLIVIA_TZ).replace(tzinfo=None)
    hoy = ahora.replace(hour=0, minute=0, second=0, microsecond=0)
    entrada(db, hoy + timedelta(hours=1), estado_fin="ERROR", origen_id=1)      # hoy, abierto
    entrada(db, hoy - timedelta(days=3), estado_fin="OK", origen_id=2)           # esta semana, cerrado
    entrada(db, hoy - timedelta(days=40), estado_fin="ERROR", origen_id=3)       # mes anterior, abierto
    entrada(db, hoy - timedelta(days=400), estado_fin="OK", origen_id=4)         # anio pasado

    resumen = resumen_anual(anio=ahora.year, db=db, usuario_actual=None)

    assert resumen.hoy == 1
    assert resumen.ultimos_7_dias == 2
    assert resumen.abiertos_ahora == 2
    mes_actual = resumen.meses[ahora.month - 1]
    assert (mes_actual.total, mes_actual.abiertos) >= (1, 1)
    assert sum(m.total for m in resumen.meses) == resumen.total_anual
    assert len(resumen.meses) == 12
