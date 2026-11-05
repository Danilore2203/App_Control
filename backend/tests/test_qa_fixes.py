"""Regresiones de la revision de QA (nov 2026)."""
from datetime import date, datetime
from unittest import mock

import pytest
from fastapi import HTTPException

from app import auth, models, schemas
from app.routers.admin import asignar_password, rechazar_solicitud
from app.services import poller
from app.services.catalogos import aplicar_push_catalogos

HOY = date(2026, 11, 5)
TS = datetime(2026, 11, 5, 8, 0)
# Contrasena ficticia de las pruebas (no es un secreto real).
CLAVE_PRUEBA = "Temporal-123"  # gitleaks:allow


def push_usuarios(*usuarios):
    envio = schemas.CatalogoPushIn(fecha=HOY, completo=True)
    envio.usuarios = schemas.UsuariosIn(upsert=list(usuarios))
    return envio


def test_el_push_de_usuarios_no_borra_la_contrasena_configurada_en_la_app(db):
    aplicar_push_catalogos(db, push_usuarios(schemas.UsuarioImportIn(username="ana", email="ana@x.com")))
    ana = db.query(models.Usuario).filter_by(username="ana").one()
    ana.password_hash = auth.hashear_password("Clave-local1")
    db.commit()

    aplicar_push_catalogos(db, push_usuarios(schemas.UsuarioImportIn(username="ana", email="ana@x.com", password_hash=None)))
    assert auth.verificar_password("Clave-local1", db.query(models.Usuario).filter_by(username="ana").one().password_hash)

    # Si MySQL SI trae un hash (alguien la cambio alla), ese manda.
    aplicar_push_catalogos(db, push_usuarios(schemas.UsuarioImportIn(username="ana", email="ana@x.com", password_hash="$2b$12$nuevo")))
    assert db.query(models.Usuario).filter_by(username="ana").one().password_hash == "$2b$12$nuevo"


def test_configurar_password_ya_no_acepta_solo_el_correo(db):
    db.add(models.Usuario(username="ana", email="ana@nuevatel.com", activo=True))
    db.commit()

    assert auth.configurar_password_local("ana", None, "ana@nuevatel.com", "Nueva-clave1", db) is None
    with pytest.raises(ValueError):
        schemas.ConfigurarPasswordIn(username="ana", correo_verificacion="ana@nuevatel.com", password_nueva="Nueva-clave1!")

    # Con la contrasena actual local si funciona.
    ana = db.query(models.Usuario).filter_by(username="ana").one()
    ana.password_hash = auth.hashear_password("Vieja-clave1")
    db.commit()
    with mock.patch.object(auth, "autenticar_contra_monitor", return_value=False):
        assert auth.configurar_password_local("ana", "Vieja-clave1", None, "Nueva-clave1", db) is not None


def test_admin_asigna_password(db):
    db.add(models.Usuario(id=1, username="ana", email="ana@nuevatel.com", activo=False))
    db.commit()

    datos = schemas.PasswordAdminIn(password=CLAVE_PRUEBA)
    out = asignar_password(usuario_id=1, payload=datos, db=db, _admin=None)

    assert out.ok
    ana = db.get(models.Usuario, 1)
    assert ana.activo and auth.verificar_password(CLAVE_PRUEBA, ana.password_hash)
    with pytest.raises(HTTPException):
        asignar_password(usuario_id=99, payload=datos, db=db, _admin=None)


def test_rechazar_solicitud_ya_procesada_falla(db):
    db.add(models.SolicitudAccesoGoogle(id=1, email="x@gmail.com", estado="aprobada"))
    db.commit()
    with pytest.raises(HTTPException):
        rechazar_solicitud(solicitud_id=1, db=db, _admin=None)


def test_reintento_de_push_no_duplica_la_alerta(db):
    db.add(models.Control(id=1, nombre="core", fuente="AIRFLOW", estado="ERROR", color="red", core="SI",
                          snapshot_fecha=HOY, snapshot_ts=TS, estado_ts=TS))
    db.add(models.Usuario(id=1, username="u", activo=True))
    db.add(models.UsuarioFcmToken(usuario_id=1, fcm_token="tok"))
    db.commit()
    usuario = db.get(models.Usuario, 1)
    token = db.query(models.UsuarioFcmToken).one()

    with mock.patch.object(poller, "enviar_alerta_push", side_effect=RuntimeError("cuota")):
        assert poller._intentar_push(db, usuario, token, 1, "msg", "t", critica=True) is False
        db.commit()
        assert poller._intentar_push(db, usuario, token, 1, "msg", "t", critica=True) is False
        db.commit()
    assert db.query(models.Alerta).count() == 1

    with mock.patch.object(poller, "enviar_alerta_push", return_value="id"):
        assert poller._intentar_push(db, usuario, token, 1, "msg", "t", critica=True) is True
        db.commit()
    (alerta,) = db.query(models.Alerta).all()
    assert alerta.enviada is True


def test_vista_evento_respeta_la_fuente(db):
    for id_, fuente, core in ((1, "AIRFLOW", "NO"), (2, "DATASTAGE", "SI")):
        db.add(models.Control(id=id_, nombre="mismo", fuente=fuente, estado="OK", color="green", core=core,
                              snapshot_fecha=HOY, snapshot_ts=TS, estado_ts=TS))
    db.commit()
    evento = models.CatalogoCambio(id=1, tipo="PROCESO", nombre="mismo", fuente="DATASTAGE", estado_nuevo="OK",
                                   color_nuevo="green", ts=TS)

    vista = poller._vista_evento(db, evento)

    assert (vista.id, vista.fuente, vista.core) == (2, "DATASTAGE", "SI")
