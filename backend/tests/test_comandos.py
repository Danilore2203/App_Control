"""Cola de comandos app -> OP_PROD (services/comandos.py)."""
from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException

from app import models, schemas
from app.services import comandos as S
from app.services.usuarios import designar_administrador


def usuario(db, username, admin=False):
    u = models.Usuario(username=username, email=f"{username}@x.com", activo=True)
    db.add(u)
    db.commit()
    if admin:
        designar_administrador(db, u.email, username)
        db.commit()
    return db.query(models.Usuario).filter_by(username=username).one()


def test_una_consulta_la_puede_pedir_cualquiera_y_op_la_resuelve(db):
    ana = usuario(db, "ana")
    c = S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.netezza.sesiones"))
    assert (c.estado, c.creado_por) == ("pendiente", "ana")

    # OP_PROD lo retira: queda en curso y no se vuelve a entregar.
    tomados = S.tomar_pendientes(db)
    assert [t.id for t in tomados] == [c.id]
    assert S.tomar_pendientes(db) == []
    S.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=True, resultado={"active": [], "idle": []}))

    visto = S.obtener_comando(db, c.id, ana)
    assert (visto.estado, visto.resultado) == ("ok", {"active": [], "idle": []})


def test_las_acciones_solo_las_piden_administradores(db):
    ana = usuario(db, "ana")
    admin = usuario(db, "root", admin=True)
    with pytest.raises(HTTPException) as exc:
        S.crear_comando(db, ana, schemas.ComandoIn(tipo="procesos.lanzar", payload={"nombre": "X"}))
    assert exc.value.status_code == 403
    c = S.crear_comando(db, admin, schemas.ComandoIn(tipo="procesos.lanzar", payload={"nombre": "X"}))
    assert c.payload == {"nombre": "X"}


def test_seguir_la_corrida_lanzada_lo_puede_pedir_cualquiera(db):
    ana = usuario(db, "ana")
    c = S.crear_comando(
        db, ana, schemas.ComandoIn(tipo="procesos.lanzar.estado", payload={"nombre": "X", "lanzado_en": "2026-11-09 14:40:00"})
    )
    assert (c.estado, c.payload["nombre"]) == ("pendiente", "X")


@pytest.mark.parametrize("tipo", [
    "ra.resumen", "ra.actualizar_todos",
    "reportes.resumen", "reportes.lanzar", "reportes.lanzar.estado", "reportes.cola.candidatos",
    "reportes.cola.iniciar", "reportes.cola.estado", "reportes.cola.detener",
])
def test_monitor_ra_y_reportes_solo_administradores(db, tipo):
    ana = usuario(db, "ana")
    admin = usuario(db, "root", admin=True)
    with pytest.raises(HTTPException) as exc:
        S.crear_comando(db, ana, schemas.ComandoIn(tipo=tipo))
    assert exc.value.status_code == 403
    assert S.crear_comando(db, admin, schemas.ComandoIn(tipo=tipo)).tipo == tipo


def test_tipo_desconocido_se_rechaza(db):
    ana = usuario(db, "ana")
    with pytest.raises(HTTPException) as exc:
        S.crear_comando(db, ana, schemas.ComandoIn(tipo="rm.rf"))
    assert exc.value.status_code == 400


def test_un_comando_que_nadie_retira_expira(db):
    ana = usuario(db, "ana")
    c = S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.netezza.sesiones"))
    db.get(models.Comando, c.id).creado_en = datetime.utcnow() - timedelta(seconds=S.EXPIRA_PENDIENTE_SEGUNDOS + 5)
    db.commit()
    visto = S.obtener_comando(db, c.id, ana)
    assert visto.estado == "expirado"
    assert "OP_PROD" in visto.error
    assert S.tomar_pendientes(db) == []


def test_solo_el_autor_o_un_admin_ven_el_comando(db):
    ana = usuario(db, "ana")
    beto = usuario(db, "beto")
    admin = usuario(db, "root", admin=True)
    c = S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.netezza.sesiones"))
    with pytest.raises(HTTPException):
        S.obtener_comando(db, c.id, beto)
    assert S.obtener_comando(db, c.id, admin).id == c.id
