from unittest import mock

from firebase_admin import messaging

from app import models
from app.services import poller


def usuario_con_token(db, id_, token):
    db.add(models.Usuario(id=id_, username=f"u{id_}", activo=True))
    db.add(models.UsuarioFcmToken(usuario_id=id_, fcm_token=token))
    db.commit()


def test_avisa_a_cada_celular_registrado(db):
    usuario_con_token(db, 1, "tok-1")
    usuario_con_token(db, 2, "tok-2")
    db.add(models.Usuario(id=3, username="sin_token", activo=True))
    db.commit()

    with mock.patch.object(poller, "enviar_actualizacion_push", return_value="id") as enviar:
        assert poller.notificar_actualizacion_app(db) == 2

    assert sorted(c.args[0] for c in enviar.call_args_list) == ["tok-1", "tok-2"]


def test_token_vencido_se_elimina_y_no_frena_a_los_demas(db):
    usuario_con_token(db, 1, "vencido")
    usuario_con_token(db, 2, "ok")

    def enviar(token):
        if token == "vencido":
            raise messaging.UnregisteredError("gone")
        return "id"

    with mock.patch.object(poller, "enviar_actualizacion_push", side_effect=enviar):
        assert poller.notificar_actualizacion_app(db) == 1

    assert [t.fcm_token for t in db.query(models.UsuarioFcmToken).all()] == ["ok"]
