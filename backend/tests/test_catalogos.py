from datetime import date, datetime

from app import models, schemas
from app.services.catalogos import aplicar_push_catalogos, estado_catalogos

HOY = date(2026, 11, 5)
AYER = date(2026, 11, 4)
TS = datetime(2026, 11, 5, 8, 0, 0)


def proceso(id_, nombre, estado="OK", color="green", fecha=HOY, ts=TS, **extra):
    return schemas.CatalogoProcesoIn(
        id=id_, nombre=nombre, fuente="AIRFLOW", estado=estado, color=color,
        snapshot_fecha=fecha, snapshot_ts=ts, estado_ts=ts, **extra,
    )


def tabla(id_, nombre, estado="OK", color="green", fecha=HOY, ts=TS):
    return schemas.CatalogoTablaIn(
        id=id_, nombre=nombre, fuente="QA_CONTROL", estado=estado, color=color,
        cantidad=10, snapshot_fecha=fecha, snapshot_ts=ts, estado_ts=ts,
    )


def evento(id_, nombre, anterior, nuevo, color="red", tipo="PROCESO", ts=TS):
    return schemas.CatalogoEventoIn(
        id=id_, tipo=tipo, nombre=nombre, fuente="AIRFLOW",
        estado_anterior=anterior, estado_nuevo=nuevo, color_nuevo=color, ts=ts,
    )


def push(fecha=HOY, completo=False, procesos=(), bajas_procesos=(), tablas=(), bajas_tablas=(), eventos=()):
    return schemas.CatalogoPushIn(
        fecha=fecha,
        completo=completo,
        procesos=schemas.CatalogoProcesosIn(upsert=list(procesos), bajas=list(bajas_procesos)),
        tablas=schemas.CatalogoTablasIn(upsert=list(tablas), bajas=list(bajas_tablas)),
        eventos=list(eventos),
    )


def test_primera_carga_inserta_todo(db):
    out = aplicar_push_catalogos(db, push(
        completo=True,
        procesos=[proceso(1, "carga_a"), proceso(2, "carga_b")],
        tablas=[tabla(10, "t_a")],
    ))

    assert out.procesos.model_dump() == {"insertadas": 2, "actualizadas": 0, "eliminadas": 0, "omitidas": 0}
    assert out.tablas.model_dump() == {"insertadas": 1, "actualizadas": 0, "eliminadas": 0, "omitidas": 0}
    assert out.eventos.model_dump() == {"insertados": 0, "ignorados": 0}
    assert db.query(models.Control).count() == 2
    assert db.query(models.Tabla).count() == 1


def test_reintento_del_mismo_envio_es_idempotente(db):
    envio = push(
        procesos=[proceso(1, "carga_a", estado="ERROR", color="red")],
        eventos=[evento(100, "carga_a", "OK", "ERROR")],
    )
    aplicar_push_catalogos(db, envio)
    out = aplicar_push_catalogos(db, envio)

    assert out.procesos.insertadas == 0 and out.procesos.actualizadas == 1
    assert out.eventos.model_dump() == {"insertados": 0, "ignorados": 1}
    assert db.query(models.Control).count() == 1
    assert db.query(models.CatalogoCambio).count() == 1


def test_cambio_incremental_actualiza_en_el_lugar_y_guarda_evento(db):
    aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "carga_a"), proceso(2, "carga_b")]))

    ts_error = datetime(2026, 11, 5, 8, 47, 0)
    out = aplicar_push_catalogos(db, push(
        procesos=[proceso(1, "carga_a", estado="ERROR", color="red", ts=ts_error)],
        eventos=[evento(100, "carga_a", "OK", "ERROR", ts=ts_error)],
    ))

    assert out.procesos.model_dump() == {"insertadas": 0, "actualizadas": 1, "eliminadas": 0, "omitidas": 0}
    fila = db.get(models.Control, 1)
    assert (fila.estado, fila.color, fila.estado_ts) == ("ERROR", "red", ts_error)
    # El otro proceso no se toco y el id sigue siendo el mismo.
    assert db.get(models.Control, 2).estado == "OK"
    assert db.query(models.Control).count() == 2
    cambio = db.get(models.CatalogoCambio, 100)
    assert (cambio.estado_anterior, cambio.estado_nuevo, cambio.ts) == ("OK", "ERROR", ts_error)


def test_bajas_borran_por_id(db):
    aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "a"), proceso(2, "b")], tablas=[tabla(10, "t")]))

    out = aplicar_push_catalogos(db, push(bajas_procesos=[2], bajas_tablas=[10]))

    assert out.procesos.eliminadas == 1 and out.tablas.eliminadas == 1
    assert [c.id for c in db.query(models.Control).all()] == [1]
    assert db.query(models.Tabla).count() == 0


def test_completo_elimina_lo_que_no_viene_solo_de_ese_dia(db):
    # Dia anterior intacto + filas de hoy "viejas" (p.ej. restos de la epoca
    # de la replica, con ids que ya no existen en MySQL).
    aplicar_push_catalogos(db, push(fecha=AYER, procesos=[proceso(90, "a", fecha=AYER)]))
    aplicar_push_catalogos(db, push(procesos=[proceso(1, "a"), proceso(2, "b"), proceso(3, "c")]))

    out = aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "a"), proceso(4, "d")]))

    assert out.procesos.model_dump() == {"insertadas": 1, "actualizadas": 1, "eliminadas": 2, "omitidas": 0}
    assert sorted(c.id for c in db.query(models.Control).all()) == [1, 4, 90]


def test_no_borra_un_proceso_que_tiene_alertas(db):
    aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "a"), proceso(2, "b")]))
    db.add(models.Alerta(control_id=2, mensaje="fallo", nivel="critica"))
    db.commit()

    out = aplicar_push_catalogos(db, push(bajas_procesos=[1, 2]))

    assert out.procesos.model_dump() == {"insertadas": 0, "actualizadas": 0, "eliminadas": 1, "omitidas": 1}
    assert [c.id for c in db.query(models.Control).all()] == [2]


def test_estado_resume_lo_recibido_del_dia(db):
    assert estado_catalogos(db, HOY).model_dump() == {
        "fecha": HOY, "procesos_hoy": 0, "tablas_hoy": 0, "eventos_hoy": 0, "ultimo_snapshot_ts": None,
        "ultimo_evento_ts": None, "ultimo_evento_id": 0, "ultimo_cambio_revisado": 0, "episodios_alerta_abiertos": 0,
        "bitacora_total": 0, "bitacora_ultima_actualizacion": None, "bitacora_locales": 0,
        "bitacora_locales_automaticas": 0, "bitacora_hoy_mysql": 0, "relaciones_total": 0, "usuarios_total": 0,
    }

    ts_tarde = datetime(2026, 11, 5, 9, 30)
    aplicar_push_catalogos(db, push(
        completo=True,
        procesos=[proceso(1, "a"), proceso(2, "b", ts=ts_tarde), proceso(90, "ayer", fecha=AYER)],
        tablas=[tabla(10, "t")],
        eventos=[evento(100, "b", "OK", "ERROR", ts=ts_tarde)],
    ))

    estado = estado_catalogos(db, HOY)
    assert (estado.procesos_hoy, estado.tablas_hoy, estado.eventos_hoy) == (2, 1, 1)
    assert estado.ultimo_snapshot_ts == ts_tarde
    assert (estado.ultimo_evento_ts, estado.ultimo_evento_id) == (ts_tarde, 100)


def usuario_mysql(username, email=None, admin=False, **extra):
    return schemas.UsuarioImportIn(username=username, email=email, **extra)


def test_usuarios_de_mysql_se_replican_por_username_sin_tocar_lo_local(db):
    # Usuario creado aca a mano (primer admin) que no existe en MySQL.
    db.add(models.Usuario(username="danilorejasperalta", email="danilorejasperalta@gmail.com",
                          email_google="danilorejasperalta@gmail.com", activo=True))
    db.commit()
    local = db.query(models.Usuario).one()
    db.add(models.Administrador(usuario_id=local.id))
    db.commit()

    envio = push(completo=True)
    envio.usuarios = schemas.UsuariosIn(
        upsert=[
            usuario_mysql("darejas", "Danilo.Rejas@nuevatel.com", nombre="Danilo Rejas", password_hash="$2b$12$x"),
            usuario_mysql("jusmartinez", "Justo.Martinez@nuevatel.com", activo=True),
            usuario_mysql("jebutron", "Jean.Butron@nuevatel.com", password_hash=""),
        ],
        administradores=["darejas", "noexiste"],
    )
    out = aplicar_push_catalogos(db, envio)

    assert out.usuarios.model_dump() == {"insertados": 3, "actualizados": 0, "administradores_nuevos": 1, "omitidos": []}
    darejas = db.query(models.Usuario).filter_by(username="darejas").one()
    assert (darejas.password_hash, darejas.email) == ("$2b$12$x", "Danilo.Rejas@nuevatel.com")
    assert db.query(models.Usuario).filter_by(username="jebutron").one().password_hash is None
    admins = {a.usuario_id for a in db.query(models.Administrador).all()}
    assert admins == {local.id, darejas.id}  # el admin local sigue, se suma el de MySQL

    # Segundo envio: actualiza en el lugar, conserva el email_google vinculado aca.
    darejas.email_google = "danilo.personal@gmail.com"
    db.commit()
    out2 = aplicar_push_catalogos(db, envio)
    assert (out2.usuarios.insertados, out2.usuarios.actualizados, out2.usuarios.administradores_nuevos) == (0, 3, 0)
    assert db.query(models.Usuario).filter_by(username="darejas").one().email_google == "danilo.personal@gmail.com"
    assert db.query(models.Usuario).count() == 4


def test_usuario_cuyo_email_ya_es_de_otro_se_omite(db):
    db.add(models.Usuario(username="local", email="danix.rp.22@gmail.com", activo=True))
    db.commit()
    envio = push()
    envio.usuarios = schemas.UsuariosIn(upsert=[usuario_mysql("danix.rp.22", "danix.rp.22@gmail.com")])

    out = aplicar_push_catalogos(db, envio)

    assert out.usuarios.omitidos == ["danix.rp.22"]
    assert db.query(models.Usuario).count() == 1


def test_bitacora_de_mysql_se_replica_por_origen_id_sin_tocar_lo_propio(db):
    db.add(models.BitacoraError(fecha_hora=TS, nombre="manual", tecnologia="AIRFLOW", descripcion="a mano",
                                estado="ERROR", estado_fin="ERROR", tipo="PROCESO"))
    db.commit()
    fila = schemas.BitacoraImportIn(
        origen_id=500, fecha_hora=TS, nombre="carga_a", tecnologia="AIRFLOW", descripcion="Proceso en error",
        estado="ERROR", estado_fin="ERROR", tipo="PROCESO",
    )
    envio = push()
    envio.bitacora = schemas.BitacoraIn(upsert=[fila])
    out = aplicar_push_catalogos(db, envio)
    assert out.bitacora.model_dump() == {"insertadas": 1, "actualizadas": 0, "eliminadas": 0}

    # Cierre del episodio alla: misma fila (mismo id local), actualizada.
    id_local = db.query(models.BitacoraError).filter_by(origen_id=500).one().id
    fila.estado_fin = "OK"
    fila.fecha_actualizacion = datetime(2026, 11, 5, 9, 3)
    fila.descripcion = "Proceso en error. Solucionado"
    out2 = aplicar_push_catalogos(db, envio)
    assert out2.bitacora.model_dump() == {"insertadas": 0, "actualizadas": 1, "eliminadas": 0}
    cerrada = db.query(models.BitacoraError).filter_by(origen_id=500).one()
    assert (cerrada.id, cerrada.estado_fin, cerrada.fecha_actualizacion) == (id_local, "OK", datetime(2026, 11, 5, 9, 3))
    assert db.query(models.BitacoraError).filter_by(nombre="manual").one().estado_fin == "ERROR"
    assert db.query(models.BitacoraError).count() == 2


def test_limpieza_borra_solo_los_episodios_locales_automaticos(db):
    from app.services.catalogos import eliminar_bitacora_local_automatica

    def fila(**kw):
        base = dict(fecha_hora=TS, nombre="p", tecnologia="AIRFLOW", descripcion="x", estado="ERROR",
                    estado_fin="ERROR", tipo="PROCESO")
        base.update(kw)
        db.add(models.BitacoraError(**base))

    fila(origen_id=1)                                   # replicada de MySQL: se queda
    fila(nombre="poller viejo")                         # local automatica: se borra
    fila(nombre="manual", creado_por_id=7)              # manual: se queda
    fila(nombre="a -> t", estado="INCOHERENCIA")        # incoherencia: se queda
    db.commit()

    assert eliminar_bitacora_local_automatica(db) == 1
    assert sorted(b.nombre for b in db.query(models.BitacoraError).all()) == ["a -> t", "manual", "p"]
    estado = estado_catalogos(db, HOY)
    assert (estado.bitacora_total, estado.bitacora_locales, estado.bitacora_locales_automaticas, estado.bitacora_hoy_mysql) == (1, 2, 0, 1)


def test_relaciones_proceso_tabla_completo_reemplaza(db):
    db.add(models.ProcesoTabla(id=99, proceso_nombre="viejo", tabla_nombre="t", tipo_relacion="ALIMENTA"))
    db.commit()
    envio = push(completo=True)
    envio.relaciones = schemas.RelacionesIn(upsert=[
        schemas.RelacionImportIn(id=1, proceso_nombre="carga_a", tabla_nombre="t_a"),
        schemas.RelacionImportIn(id=2, proceso_nombre="carga_b", tabla_nombre="t_b", activo=False),
    ])

    out = aplicar_push_catalogos(db, envio)

    assert out.relaciones.model_dump() == {"insertadas": 2, "actualizadas": 0, "eliminadas": 1, "omitidas": 0}
    assert sorted(r.id for r in db.query(models.ProcesoTabla).all()) == [1, 2]


def test_un_fallo_no_deja_el_envio_a_medias(db):
    aplicar_push_catalogos(db, push(completo=True, procesos=[proceso(1, "a")]))
    # Evento con nombre None viola NOT NULL al hacer flush: la transaccion
    # entera (incluida la actualizacion del proceso) debe deshacerse.
    envio = push(
        procesos=[proceso(1, "a", estado="ERROR", color="red")],
        eventos=[evento(100, "a", "OK", "ERROR")],
    )
    envio.eventos[0].nombre = None  # type: ignore[assignment]

    try:
        aplicar_push_catalogos(db, envio)
    except Exception:
        pass
    else:
        raise AssertionError("se esperaba que fallara")

    assert db.get(models.Control, 1).estado == "OK"
    assert db.query(models.CatalogoCambio).count() == 0


def test_los_ids_vigentes_borran_lo_que_mysql_ya_no_tiene(db):
    def fila(origen_id=None, fecha=TS, **kw):
        base = dict(origen_id=origen_id, fecha_hora=fecha, nombre="p", tecnologia="AIRFLOW", descripcion="x",
                    estado="ERROR", estado_fin="ERROR", tipo="PROCESO")
        base.update(kw)
        db.add(models.BitacoraError(**base))

    fila(origen_id=1)                                        # sigue en MySQL: se queda
    fila(origen_id=2)                                        # fusionada alla: se borra
    fila(origen_id=3, fecha=datetime(2026, 10, 1, 8, 0))    # fuera de la ventana: no se toca
    fila(nombre="manual", creado_por_id=7)                   # propia de la app: no se toca
    fila(nombre="incoherencia", estado="INCOHERENCIA")       # propia de la app: no se toca
    db.commit()

    envio = push()
    envio.bitacora = schemas.BitacoraIn(
        upsert=[],
        vigentes=schemas.BitacoraVigentesIn(desde=date(2026, 11, 1), ids=[1, 999]),
    )
    out = aplicar_push_catalogos(db, envio)

    assert out.bitacora.model_dump() == {"insertadas": 0, "actualizadas": 0, "eliminadas": 1}
    restantes = {(e.origen_id, e.nombre) for e in db.query(models.BitacoraError).all()}
    assert restantes == {(1, "p"), (3, "p"), (None, "manual"), (None, "incoherencia")}
