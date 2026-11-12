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


PC_150 = "s2nt-control-bi"
PC_JHOJANS = "10.1.1.1 · python-requests/2.31.0"  # OP de antes del 12/11: no dice su nombre


def _pg_prod(db, quien):
    return S.crear_comando(db, quien, schemas.ComandoIn(tipo="infra.postgres.sesiones", payload={"entorno": "prod"}))


def test_equipo_de_usa_el_nombre_de_la_pc_o_ip_y_agente():
    assert S.equipo_de({"x-op-equipo": " S2NT-CONTROL-BI "}, "1.2.3.4") == ("S2NT-CONTROL-BI", True)
    assert S.equipo_de({"x-forwarded-for": "200.85.145.126, 10.0.0.1", "user-agent": "python-requests/2.32.3"}, "10.0.0.9") == (
        "200.85.145.126 · python-requests/2.32.3",
        False,
    )


def test_con_el_150_atendiendo_otra_pc_sin_nombre_no_recibe_nada(db):
    ana = usuario(db, "ana")
    assert S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_150, identificado=True) == []
    c = _pg_prod(db, ana)
    # La PC de un compañero con OP abierto como primaria consulta primero: no se lo lleva.
    assert S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_JHOJANS) == []
    assert db.get(models.Comando, c.id).estado == "pendiente"
    tomados = S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_150, identificado=True)
    assert [t.id for t in tomados] == [c.id]
    assert tomados[0].tomado_por == PC_150

    # Si el .150 se apaga (mas de 90 s sin consultar), las demas vuelven a atender.
    db.get(models.EquipoOp, PC_150).visto_en -= timedelta(seconds=S.EQUIPO_ACTIVO_SEGUNDOS + 5)
    db.commit()
    otro = _pg_prod(db, ana)
    assert [t.id for t in S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_JHOJANS)] == [otro.id]


def test_entre_dos_con_nombre_atiende_la_que_llega_a_pg_y_lleva_mas_tiempo(db):
    ana = usuario(db, "ana")
    S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_150, identificado=True)
    S.tomar_pendientes(db, tipos=TIPOS_OP, equipo="JHOJRODRIGUEZ-LT", identificado=True)
    c = _pg_prod(db, ana)
    assert S.tomar_pendientes(db, tipos=TIPOS_OP, equipo="JHOJRODRIGUEZ-LT", identificado=True) == []
    assert [t.id for t in S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_150, identificado=True)] == [c.id]
    equipos = {e.nombre: e for e in S.listar_equipos(db)}
    assert equipos[PC_150].titular and not equipos["JHOJRODRIGUEZ-LT"].titular

    # Aunque el .150 se reinicie y vuelva despues, la que no llega a PG no se queda con la cola.
    db.get(models.EquipoOp, PC_150).activo_desde += timedelta(hours=1)
    db.get(models.EquipoOp, "JHOJRODRIGUEZ-LT").sin_pg_hasta = datetime.utcnow() + timedelta(minutes=5)
    db.commit()
    assert {e.nombre for e in S.listar_equipos(db) if e.titular} == {PC_150}


def test_la_pc_que_no_pudo_entrar_a_pg_ya_no_recibe_esos_pedidos_si_hay_otra(db):
    ana = usuario(db, "ana")
    # Dos copias viejas (sin nombre) que salen por distinta IP: atienden las dos, como antes.
    S.tomar_pendientes(db, tipos=TIPOS_OP, equipo="10.2.2.2 · python-requests/2.32.3")
    c = _pg_prod(db, ana)
    assert [t.id for t in S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_JHOJANS)] == [c.id]
    S.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=False, error=SIN_ACCESO))
    assert db.get(models.EquipoOp, PC_JHOJANS).sin_pg_hasta is not None

    # Vuelve a la cola, pero esa PC ya no lo recibe (Netezza si); la otra, si.
    nz = S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.netezza.sesiones"))
    assert [t.id for t in S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_JHOJANS)] == [nz.id]
    assert [t.id for t in S.tomar_pendientes(db, tipos=TIPOS_OP, equipo="10.2.2.2 · python-requests/2.32.3")] == [c.id]


def test_si_es_la_unica_que_atiende_igual_lo_intenta(db):
    ana = usuario(db, "ana")
    c = _pg_prod(db, ana)
    S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_JHOJANS)
    S.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=False, error=SIN_ACCESO))
    # No hay otra copia: no se queda esperando hasta expirar, lo vuelve a intentar y al final falla con el motivo.
    assert [t.id for t in S.tomar_pendientes(db, tipos=TIPOS_OP, equipo=PC_JHOJANS)] == [c.id]


def test_otros_errores_de_postgres_no_se_reintentan(db):
    ana = usuario(db, "ana")
    c = S.crear_comando(db, ana, schemas.ComandoIn(tipo="infra.postgres.sesiones", payload={"entorno": "prod"}))
    S.tomar_pendientes(db, tipos=TIPOS_OP)
    salida = S.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=False, error="canceling statement due to statement timeout"))
    assert (salida.estado, salida.error) == ("error", "canceling statement due to statement timeout")
