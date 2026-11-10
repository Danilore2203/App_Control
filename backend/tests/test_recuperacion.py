"""Recuperar la contrasena por correo (services/recuperacion.py) y hashes de la web."""
import json
from datetime import datetime, timedelta

from werkzeug.security import generate_password_hash

from app import auth, models, schemas
from app.services import comandos as C
from app.services import recuperacion as R
from app.services.catalogos import aplicar_push_catalogos

T0 = datetime(2026, 11, 10, 15, 0)
NUEVA = "Prueba#2026"


def usuario(db, username="ana", email="Ana.Perez@nuevatel.com", **extra):
    u = models.Usuario(username=username, nombre="Ana Pérez", email=email, activo=True, **extra)
    db.add(u)
    db.commit()
    return u


def codigo_enviado(db) -> str:
    """El codigo como lo recibe OP_PROD para mandarlo por correo (directo de
    la fila: tomar_pendientes usa el reloj real y T0 es fijo)."""
    cmd = db.query(models.Comando).filter_by(tipo=R.TIPO_COMANDO).order_by(models.Comando.id.desc()).first()
    return json.loads(cmd.payload)["codigo"]


def test_pedir_codigo_deja_el_correo_en_la_cola_y_guarda_solo_un_hmac(db):
    ana = usuario(db)
    assert R.solicitar(db, "ana", ahora=T0) is True

    fila = db.query(models.CodigoRecuperacion).one()
    (cmd,) = db.query(models.Comando).all()
    payload = json.loads(cmd.payload)
    assert (cmd.tipo, cmd.estado, cmd.creado_por_id) == (R.TIPO_COMANDO, "pendiente", ana.id)
    assert payload["para"] == "Ana.Perez@nuevatel.com"
    assert (payload["nombre"], payload["usuario"], payload["minutos"]) == ("Ana Pérez", "ana", 15)
    assert len(payload["codigo"]) == 6 and payload["codigo"].isdigit()
    assert payload["codigo"] not in fila.codigo_hash
    assert fila.expira_en == T0 + timedelta(minutes=15)


def test_se_puede_pedir_con_el_correo_y_no_dice_si_la_cuenta_existe(db):
    usuario(db)
    usuario(db, "sin_correo", email=None)
    usuario(db, "baja", email="baja@nuevatel.com").activo = False
    db.commit()

    assert R.solicitar(db, "  ana.perez@NUEVATEL.com ", ahora=T0) is True
    assert R.solicitar(db, "noexiste", ahora=T0) is False
    assert R.solicitar(db, "sin_correo", ahora=T0) is False
    assert R.solicitar(db, "baja", ahora=T0) is False
    assert db.query(models.Comando).count() == 1


def test_como_mucho_tres_codigos_por_hora_y_el_nuevo_anula_el_anterior(db):
    usuario(db)
    for i in range(3):
        assert R.solicitar(db, "ana", ahora=T0 + timedelta(minutes=i)) is True
    assert R.solicitar(db, "ana", ahora=T0 + timedelta(minutes=10)) is False
    assert R.solicitar(db, "ana", ahora=T0 + timedelta(minutes=61)) is True
    vigentes = db.query(models.CodigoRecuperacion).filter(models.CodigoRecuperacion.usado_en.is_(None)).count()
    assert vigentes == 1


def test_con_el_codigo_cambia_la_contrasena_una_sola_vez(db):
    ana = usuario(db, password_hash=generate_password_hash("vieja"), password_hash_web="x")
    R.solicitar(db, "ana", ahora=T0)
    codigo = codigo_enviado(db)

    assert R.restablecer(db, "ana", codigo, NUEVA, ahora=T0 + timedelta(minutes=5)).id == ana.id
    db.refresh(ana)
    assert auth.verificar_password(NUEVA, ana.password_hash)
    assert not auth.verificar_password("vieja", ana.password_hash)
    assert ana.password_hash_web == "x"  # lo de la web no se toca
    # Ya usado: no sirve de nuevo.
    assert R.restablecer(db, "ana", codigo, "Otra#2026", ahora=T0 + timedelta(minutes=6)) is None


def test_codigo_vencido_o_de_otra_cuenta_no_sirve(db):
    usuario(db)
    usuario(db, "beto", email="beto@nuevatel.com")
    R.solicitar(db, "ana", ahora=T0)
    codigo = codigo_enviado(db)

    assert R.restablecer(db, "beto", codigo, NUEVA, ahora=T0) is None
    assert R.restablecer(db, "ana", codigo, NUEVA, ahora=T0 + timedelta(minutes=16)) is None


def test_cinco_intentos_fallidos_anulan_el_codigo(db):
    usuario(db)
    R.solicitar(db, "ana", ahora=T0)
    codigo = codigo_enviado(db)
    malo = "000000" if codigo != "000000" else "111111"
    for _ in range(R.MAX_INTENTOS):
        assert R.restablecer(db, "ana", malo, NUEVA, ahora=T0) is None
    assert R.restablecer(db, "ana", codigo, NUEVA, ahora=T0) is None


def test_el_codigo_solo_lo_ve_op_y_se_borra_al_mandar_el_correo(db):
    admin = usuario(db, "root", email="root@nuevatel.com")
    db.add(models.Administrador(usuario_id=admin.id))
    db.commit()
    R.solicitar(db, "root", ahora=datetime.utcnow())
    (cmd,) = db.query(models.Comando).all()

    assert C.listar_recientes(db)[0].payload["codigo"] == "***"
    assert C.obtener_comando(db, cmd.id, admin).payload["codigo"] == "***"
    assert C.tomar_pendientes(db)[0].payload["codigo"].isdigit()

    salida = C.registrar_resultado(db, cmd.id, schemas.ComandoResultadoIn(ok=True, resultado={"enviado_a": "r***@nuevatel.com"}))
    assert salida.payload["codigo"] == "***"
    db.refresh(cmd)
    assert json.loads(cmd.payload)["codigo"] == "***"
    assert json.loads(cmd.payload)["para"] == "root@nuevatel.com"


def test_si_op_no_lo_retira_tambien_se_borra_al_expirar(db):
    usuario(db)
    R.solicitar(db, "ana", ahora=T0)
    C.expirar_vencidos(db, ahora=T0 + timedelta(minutes=5))
    (cmd,) = db.query(models.Comando).all()
    assert cmd.estado == "expirado"
    assert json.loads(cmd.payload)["codigo"] == "***"


def test_la_app_no_puede_pedir_el_comando_de_correo(db):
    import pytest
    from fastapi import HTTPException

    ana = usuario(db)
    with pytest.raises(HTTPException) as exc:
        C.crear_comando(db, ana, schemas.ComandoIn(tipo=R.TIPO_COMANDO, payload={"para": "x@y.com", "codigo": "1"}))
    assert exc.value.status_code == 400


def test_acepta_contrasenas_hechas_en_la_web_y_un_hash_raro_no_rompe_el_login(db):
    assert auth.verificar_password("Web#123", generate_password_hash("Web#123"))
    assert auth.verificar_password("Web#123", generate_password_hash("Web#123", method="pbkdf2:sha256"))
    assert not auth.verificar_password("otra", generate_password_hash("Web#123"))
    assert auth.verificar_password("App#123", auth.hashear_password("App#123"))
    assert auth.verificar_password("x", "no-es-un-hash") is False
    assert auth.verificar_password("", auth.hashear_password("App#123")) is False


def test_el_push_de_la_web_no_pisa_una_contrasena_cambiada_en_la_app(db):
    def push(hash_web):
        aplicar_push_catalogos(db, schemas.CatalogoPushIn(
            fecha="2026-11-10", completo=False,
            usuarios=schemas.UsuariosIn(upsert=[schemas.UsuarioImportIn(
                username="ana", email="Ana.Perez@nuevatel.com", password_hash=hash_web)]),
        ))
        db.commit()
        return db.query(models.Usuario).filter_by(username="ana").one()

    web_1 = generate_password_hash("Web#1")
    ana = push(web_1)
    assert (ana.password_hash, ana.password_hash_web) == (web_1, web_1)

    # Cambia la contrasena en la app; el push siguiente trae el mismo hash de la web.
    ana.password_hash = auth.hashear_password(NUEVA)
    db.commit()
    ana = push(web_1)
    assert auth.verificar_password(NUEVA, ana.password_hash)

    # Si un administrador la cambia en la web, esa manda.
    web_2 = generate_password_hash("Web#2")
    ana = push(web_2)
    assert (ana.password_hash, ana.password_hash_web) == (web_2, web_2)


def test_los_correos_que_no_salieron_no_cuentan_para_el_limite(db):
    usuario(db)
    for i in range(3):
        R.solicitar(db, "ana", ahora=T0 + timedelta(minutes=i))
    # OP_PROD estaba sin reiniciar: los tres volvieron con error.
    for c in db.query(models.Comando).all():
        C.registrar_resultado(db, c.id, schemas.ComandoResultadoIn(ok=False, error="Comando desconocido para OP_PROD"))
    assert R.solicitar(db, "ana", ahora=T0 + timedelta(minutes=5)) is True


def test_el_usuario_se_encuentra_aunque_el_celular_ponga_mayuscula(db):
    usuario(db, "darejas", email="d@nuevatel.com")
    assert R.solicitar(db, "Darejas", ahora=T0) is True
    assert auth.buscar_usuario_por_identificador("DAREJAS", db).username == "darejas"


def test_diagnostico_dice_por_que_no_llega_sin_mostrar_el_codigo(db):
    assert R.diagnostico(db, "nadie") == {"encontrado": False}
    usuario(db)
    R.solicitar(db, "ana", ahora=datetime.utcnow())
    (cmd,) = db.query(models.Comando).all()
    codigo = json.loads(cmd.payload)["codigo"]
    C.registrar_resultado(db, cmd.id, schemas.ComandoResultadoIn(ok=False, error="SMTP caido"))

    d = R.diagnostico(db, "ana")
    assert (d["correo"], d["puede_pedir"], d["codigos_ultima_hora"]) == ("A***@nuevatel.com", True, 0)
    assert [(c["estado"], c["error"]) for c in d["correos_24h"]] == [("error", "SMTP caido")]
    assert codigo not in json.dumps(d)
