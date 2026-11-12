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
    "ra.resumen", "ra.actualizar_todos", "ra.detalle", "robby.verificar", "robby.insertar",
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


def test_bloqueos_netezza_los_ve_cualquiera_y_matar_solo_administradores(db):
    ana = usuario(db, "ana")
    admin = usuario(db, "root", admin=True)
    assert S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.netezza.bloqueos")).estado == "pendiente"
    with pytest.raises(HTTPException) as exc:
        S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.netezza.kill", payload={"session_id": 7}))
    assert exc.value.status_code == 403
    assert S.crear_comando(db, admin, schemas.ComandoIn(tipo="infra.netezza.kill", payload={"session_id": 7})).payload == {"session_id": 7}


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


def test_soporte_ve_los_ultimos_de_un_tipo_sin_datos_reservados(db):
    from app.routers.internal import comandos_ultimos
    from app.services import recuperacion

    ana = usuario(db, "ana")
    S.crear_comando(db, ana, schemas.ComandoIn(tipo="procesos.corriendo"))
    recuperacion.solicitar(db, "ana")
    corriendo = comandos_ultimos(tipo="procesos.corriendo", db=db)
    assert [c.tipo for c in corriendo] == ["procesos.corriendo"]
    (correo,) = comandos_ultimos(tipo=recuperacion.TIPO_COMANDO, db=db)
    assert correo.payload["codigo"] == "***"
    assert db.query(models.Comando).filter_by(estado="pendiente").count() == 2  # no retira nada


SIN_ACCESO = (
    'connection to server at "10.49.4.22", port 5432 failed: server does not support SSL, but SSL was required '
    "Revisa BD, puerto, SSL y que el servidor permita tu IP."
)
TIPOS_OP = {"infra.postgres.sesiones", "infra.netezza.sesiones"}


def test_si_otra_pc_no_puede_entrar_a_pg_prod_el_pedido_vuelve_a_la_cola_para_el_150(db):
    ana = usuario(db, "ana")
    c = S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.postgres.sesiones", payload={"entorno": "prod"}))
    # Lo retira la PC de un compañero con OP abierto como primaria: no llega a PG PROD.
    S.tomar_pendientes(db, tipos=TIPOS_OP)
    salida = S.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=False, error=SIN_ACCESO))
    assert salida.estado == "pendiente"  # la app sigue esperando
    # El .150 lo toma en su siguiente consulta y responde bien.
    assert [t.id for t in S.tomar_pendientes(db, tipos=TIPOS_OP)] == [c.id]
    S.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=True, resultado={"rows": []}))
    assert S.obtener_comando(db, c.id, ana).estado == "ok"


def test_si_nadie_puede_entrar_a_pg_prod_falla_y_dice_por_que(db):
    ana = usuario(db, "ana")
    c = S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.postgres.sesiones", payload={"entorno": "prod"}))
    for _ in range(S.REINTENTOS_SIN_ACCESO + 1):
        S.tomar_pendientes(db, tipos=TIPOS_OP)
        salida = S.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=False, error=SIN_ACCESO))
    assert salida.estado == "error"
    assert salida.error.startswith("connection to server")
    assert "solo entra el servidor .150" in salida.error


def test_otros_errores_de_postgres_no_se_reintentan(db):
    ana = usuario(db, "ana")
    c = S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.postgres.sesiones", payload={"entorno": "prod"}))
    S.tomar_pendientes(db, tipos=TIPOS_OP)
    salida = S.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=False, error="canceling statement due to statement timeout"))
    assert (salida.estado, salida.error) == ("error", "canceling statement due to statement timeout")
