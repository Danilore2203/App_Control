from app import models
from app.services.usuarios import designar_administrador


def es_admin(db, usuario):
    return db.query(models.Administrador).filter(models.Administrador.usuario_id == usuario.id).count() == 1


def test_crea_el_usuario_y_lo_hace_admin_en_base_vacia(db):
    usuario = designar_administrador(db, "Danilo.Rejas@gmail.com", nombre="Danilo")

    assert (usuario.username, usuario.email, usuario.email_google, usuario.activo) == (
        "Danilo.Rejas", "Danilo.Rejas@gmail.com", "Danilo.Rejas@gmail.com", True,
    )
    assert es_admin(db, usuario)


def test_es_idempotente(db):
    a = designar_administrador(db, "x@nuevatel.com")
    b = designar_administrador(db, "X@nuevatel.com")

    assert a.id == b.id
    assert db.query(models.Usuario).count() == 1
    assert db.query(models.Administrador).count() == 1


def test_usuario_existente_por_email_google_no_se_duplica(db):
    db.add(models.Usuario(id=5, username="jperez", email="jperez@nuevatel.com", email_google="jp@gmail.com", activo=False))
    db.commit()

    usuario = designar_administrador(db, "jp@gmail.com")

    assert usuario.id == 5 and usuario.activo is True
    assert es_admin(db, usuario)
    assert db.query(models.Usuario).count() == 1


def test_aprueba_la_solicitud_google_pendiente_del_mismo_correo(db):
    db.add(models.SolicitudAccesoGoogle(email="nuevo@gmail.com", nombre="Nuevo", estado="pendiente"))
    db.commit()

    designar_administrador(db, "nuevo@gmail.com")

    assert db.query(models.SolicitudAccesoGoogle).one().estado == "aprobada"
