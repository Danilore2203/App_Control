"""Alarmas de infraestructura (congestion en Netezza) que avisa OP_PROD."""
from datetime import datetime, timedelta
from unittest import mock

from app import models, schemas
from app.services import alertas_infra as A

T0 = datetime(2026, 11, 12, 14, 0)
CLAVE = "netezza.congestion"


def _usuarios_con_token(db, n=2):
    for i in range(n):
        u = models.Usuario(username=f"u{i}", email=f"u{i}@x.com", activo=True)
        db.add(u)
        db.flush()
        db.add(models.UsuarioFcmToken(usuario_id=u.id, fcm_token=f"tok{i}"))
    db.commit()


def _aviso(activa, mensaje="La sesión 123 frena a 3 sesiones; la más vieja espera 14 min."):
    return schemas.AlertaInfraIn(clave=CLAVE, activa=activa, titulo="Netezza: bloqueo pesado" if activa else "", mensaje=mensaje if activa else "")


def test_abre_con_alarma_critica_y_no_repite_mientras_sigue(db):
    _usuarios_con_token(db)
    with mock.patch.object(A, "enviar_alerta_push") as push:
        out = A.registrar(db, _aviso(True), ahora=T0)
        assert out.abierta
        assert push.call_count == 2
        assert all(c.kwargs["critica"] and c.kwargs["tipo"] == "alerta_critica" for c in push.call_args_list)
        assert push.call_args.kwargs["titulo"] == "Netezza: bloqueo pesado"

        # OP sigue avisando cada pocos minutos: no vuelve a sonar.
        A.registrar(db, _aviso(True, "La sesión 123 frena a 5 sesiones."), ahora=T0 + timedelta(minutes=5))
        assert push.call_count == 2
        assert db.get(models.AlertaInfra, CLAVE).mensaje == "La sesión 123 frena a 5 sesiones."

        # A los 30 min: recordatorio comun (sin alarma).
        A.registrar(db, _aviso(True), ahora=T0 + timedelta(minutes=31))
        assert push.call_count == 4
        recordatorio = push.call_args_list[-1].kwargs
        assert (recordatorio["critica"], recordatorio["tipo"]) == (False, "alerta_normal")
        assert recordatorio["titulo"].startswith("Sigue:")


def test_cierra_con_aviso_comun_y_queda_en_el_historial(db):
    _usuarios_con_token(db, n=1)
    with mock.patch.object(A, "enviar_alerta_push") as push:
        A.registrar(db, _aviso(True), ahora=T0)
        out = A.registrar(db, _aviso(False), ahora=T0 + timedelta(minutes=12))
    assert not out.abierta
    assert push.call_args.kwargs["critica"] is False
    assert "12 min" in push.call_args.kwargs["cuerpo"]
    lista = A.listar(db)
    assert lista.activas == []
    assert [e.tipo for e in lista.eventos] == ["cierra", "abre"]


def test_cerrar_algo_que_no_estaba_abierto_no_avisa(db):
    _usuarios_con_token(db, n=1)
    with mock.patch.object(A, "enviar_alerta_push") as push:
        A.registrar(db, _aviso(False), ahora=T0)  # OP recien arrancado, todo normal
    push.assert_not_called()
    assert A.listar(db).eventos == []


def test_un_token_vencido_se_borra_y_los_demas_reciben(db):
    from firebase_admin import messaging

    _usuarios_con_token(db, n=2)

    def push(token, **_):
        if token == "tok0":
            raise messaging.UnregisteredError("vencido")

    with mock.patch.object(A, "enviar_alerta_push", side_effect=push):
        A.registrar(db, _aviso(True), ahora=T0)
    assert [t.fcm_token for t in db.query(models.UsuarioFcmToken).all()] == ["tok1"]
