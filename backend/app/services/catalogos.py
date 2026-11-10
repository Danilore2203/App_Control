"""Recepcion de los catalogos que OP_PROD empuja por HTTPS.

Antes los catalogos llegaban por una replica MySQL -> Supabase que copiaba
tablas enteras cada minuto, y el poller de aca los sondeaba cada minuto para
descubrir que habia cambiado. Ahora OP_PROD, al terminar cada snapshot (cada
5 min), manda SOLO lo que cambio en ese ciclo:

  - `procesos` / `tablas`: filas a insertar-o-actualizar (upsert por id de
    MySQL, que desde el cambio de OP_PROD es estable durante todo el dia) y
    los ids que desaparecieron (`bajas`).
  - `eventos`: un registro por cada cambio de estado (id de
    c137.dataops_catalogo_cambios). Es lo que recorre el poller para la
    bitacora.
  - `completo=True`: el envio trae TODAS las filas del dia `fecha` (primera
    carga del dia, o resincronizacion despues de un fallo): las filas de ese
    dia que no vengan en el envio se eliminan.

Todo es idempotente: si OP_PROD reintenta el mismo envio (p.ej. porque se
le corto la red antes de recibir la respuesta), el resultado es el mismo.
"""
import logging
from datetime import datetime
from typing import Iterable, Type

from sqlalchemy import func
from sqlalchemy.orm import Session

from app import models, schemas

logger = logging.getLogger(__name__)


def _ids_referenciados_por_alertas(db: Session, ids: Iterable[int]) -> set[int]:
    """alertas.control_id tiene FK a dataops_catalogo_procesos: una fila de
    proceso que ya tiene alertas no se puede borrar sin romper la FK. Se
    deja (es historia del dia) y se informa como omitida."""
    ids = list(ids)
    if not ids:
        return set()
    filas = db.query(models.Alerta.control_id).filter(models.Alerta.control_id.in_(ids)).distinct().all()
    return {control_id for (control_id,) in filas}


def _aplicar_catalogo(
    db: Session,
    modelo: Type[models.Base],
    seccion: schemas.CatalogoProcesosIn | schemas.CatalogoTablasIn,
    fecha,
    completo: bool,
) -> schemas.CatalogoSeccionOut:
    columnas = {c.name for c in modelo.__table__.columns}
    ids_enviados = [fila.id for fila in seccion.upsert]

    existentes = {}
    if ids_enviados:
        existentes = {obj.id: obj for obj in db.query(modelo).filter(modelo.id.in_(ids_enviados)).all()}

    insertadas = actualizadas = 0
    for fila in seccion.upsert:
        # exclude_unset: un campo que el envio no trae no se pisa. Un OP_PROD viejo manda las
        # tablas sin «core»; sin esto les borraba la marca en cada envio.
        datos = {k: v for k, v in fila.model_dump(exclude_unset=True).items() if k in columnas}
        obj = existentes.get(fila.id)
        if obj is None:
            db.add(modelo(**datos))
            insertadas += 1
        else:
            for k, v in datos.items():
                setattr(obj, k, v)
            actualizadas += 1
    # Las filas nuevas tienen que estar en la base antes de calcular las
    # bajas del modo completo, si no se borrarian a si mismas.
    db.flush()

    a_borrar: set[int] = set(seccion.bajas)
    advertencia = None
    if completo:
        consulta = db.query(modelo.id).filter(modelo.snapshot_fecha == fecha)
        if ids_enviados:
            consulta = consulta.filter(modelo.id.notin_(ids_enviados))
        faltantes = [id_ for (id_,) in consulta.all()]
        if _envio_sospechosamente_chico(len(ids_enviados), len(ids_enviados) + len(faltantes)):
            # Un "completo" con una fraccion de lo que hay (origen a medias,
            # otra copia de OP_PROD contra una base vacia) vaciaria el dia
            # entero. Se aplican las altas/cambios pero no las bajas.
            advertencia = (
                f"completo con {len(ids_enviados)} filas contra {len(ids_enviados) + len(faltantes)} existentes: "
                "no se borra nada"
            )
            logger.warning("%s: %s", modelo.__tablename__, advertencia)
        else:
            a_borrar.update(faltantes)

    omitidas: set[int] = set()
    if a_borrar and modelo is models.Control:
        omitidas = _ids_referenciados_por_alertas(db, a_borrar)
        a_borrar -= omitidas

    eliminadas = 0
    if a_borrar:
        eliminadas = (
            db.query(modelo).filter(modelo.id.in_(list(a_borrar))).delete(synchronize_session=False)
        )

    return schemas.CatalogoSeccionOut(
        insertadas=insertadas,
        actualizadas=actualizadas,
        eliminadas=eliminadas,
        omitidas=len(omitidas),
        advertencia=advertencia,
    )


# Un envio que reemplaza "todo" pero trae menos de la mitad de lo que ya hay
# (con al menos este minimo existente) se trata como incompleto: se aplica
# lo que trae y no se borra lo demas. Evita que una copia de OP_PROD contra
# una base vacia, o un snapshot a medias, vacie la app (paso el 9/11/2026:
# un completo con 20 procesos y 0 ids de bitacora borro el dia y un mes).
_MINIMO_PARA_COMPARAR = 20


def _envio_sospechosamente_chico(enviadas: int, existentes: int) -> bool:
    return existentes >= _MINIMO_PARA_COMPARAR and enviadas < existentes / 2


def _aplicar_eventos(db: Session, eventos: list[schemas.CatalogoEventoIn]) -> schemas.CatalogoEventosOut:
    if not eventos:
        return schemas.CatalogoEventosOut(insertados=0, ignorados=0)
    ids = [e.id for e in eventos]
    ya_estan = {id_ for (id_,) in db.query(models.CatalogoCambio.id).filter(models.CatalogoCambio.id.in_(ids)).all()}
    insertados = 0
    for evento in eventos:
        if evento.id in ya_estan:
            continue
        db.add(models.CatalogoCambio(**evento.model_dump()))
        ya_estan.add(evento.id)
        insertados += 1
    return schemas.CatalogoEventosOut(insertados=insertados, ignorados=len(eventos) - insertados)


def _aplicar_usuarios(db: Session, seccion: schemas.UsuariosIn) -> schemas.UsuariosOut:
    """Replica la tabla usuarios de MySQL (cuentas del monitor web) por
    username. MySQL manda en todo menos en lo que es propio de la app: si un
    usuario ya tiene email_google vinculado aca y alla viene vacio, se
    conserva. Nunca borra usuarios. Los administradores de MySQL se suman a
    los de aca, y el que deja de serlo alla deja de serlo aca; los designados
    en la app (p.ej. el primero, por /internal/administradores) se quedan."""
    from sqlalchemy import func

    por_username = {u.username.lower(): u for u in db.query(models.Usuario).all()}
    insertados = actualizados = 0
    omitidos: list[str] = []

    for fila in seccion.upsert:
        clave = fila.username.strip().lower()
        existente = por_username.get(clave)
        # Un email ya usado por OTRO usuario local (p.ej. creado a mano con el
        # correo de Google) rompe el login por email: se salta la fila y se
        # informa, en vez de dejar dos cuentas respondiendo al mismo correo.
        emails = [e.lower() for e in (fila.email, fila.email_google) if e]
        if emails:
            duenio = (
                db.query(models.Usuario)
                .filter(
                    (func.lower(models.Usuario.email).in_(emails)) | (func.lower(models.Usuario.email_google).in_(emails))
                )
                .first()
            )
            if duenio is not None and (existente is None or duenio.id != existente.id):
                omitidos.append(fila.username)
                continue

        if existente is None:
            existente = models.Usuario(username=fila.username.strip())
            db.add(existente)
            por_username[clave] = existente
            insertados += 1
        else:
            actualizados += 1
        existente.nombre = fila.nombre
        existente.email = fila.email
        # La contrasena local que un usuario configuro en la app NO se pisa
        # con un NULL de MySQL (alla casi nadie tiene hash), ni con el mismo
        # hash de la web que ya llego antes: solo se toma el de MySQL cuando
        # cambio alla. Si no, cada push devolvia la contrasena vieja de la web
        # encima de la que el usuario cambio en la app.
        if fila.password_hash and fila.password_hash != existente.password_hash_web:
            existente.password_hash = fila.password_hash
            existente.password_hash_web = fila.password_hash
        existente.activo = fila.activo
        if fila.fecha_creacion is not None:
            existente.fecha_creacion = fila.fecha_creacion
        if fila.email_google:
            existente.email_google = fila.email_google
    db.flush()

    nuevos_admin = quitados_admin = 0
    admins_web: set[int] = set()
    for username in seccion.administradores:
        usuario = por_username.get(username.strip().lower())
        if usuario is None:
            continue
        admins_web.add(usuario.id)
        ya = db.query(models.Administrador).filter(models.Administrador.usuario_id == usuario.id).first()
        if ya is None:
            db.add(models.Administrador(usuario_id=usuario.id, origen="web"))
            nuevos_admin += 1
        elif ya.origen is None:
            ya.origen = "web"

    # Quien dejo de ser administrador en la web deja de serlo aca. Solo los
    # que vinieron de la web: los designados en la app se quedan. Una lista
    # vacia se ignora: es mas probable una lectura fallida en OP_PROD que una
    # web sin ningun administrador, y vaciarla dejaria la app sin ninguno.
    if admins_web:
        for admin in db.query(models.Administrador).filter(models.Administrador.origen == "web").all():
            if admin.usuario_id not in admins_web:
                db.delete(admin)
                quitados_admin += 1

    return schemas.UsuariosOut(
        insertados=insertados,
        actualizados=actualizados,
        administradores_nuevos=nuevos_admin,
        administradores_quitados=quitados_admin,
        omitidos=omitidos,
    )


def _aplicar_bitacora(db: Session, seccion: schemas.BitacoraIn) -> schemas.BitacoraOut:
    """Refleja filas de c137.bitacora_errores por origen_id. Las entradas
    propias de la app (origen_id NULL: manuales e incoherencias) no se tocan.
    Con `vigentes`, ademas se eliminan las reflejadas de esa ventana que
    MySQL ya no tiene (fusion de duplicados, borrados desde la web): sin
    eso la app acumulaba filas que la web ya no mostraba."""
    insertadas = actualizadas = 0
    if seccion.upsert:
        ids = [f.origen_id for f in seccion.upsert]
        existentes = {
            e.origen_id: e
            for e in db.query(models.BitacoraError).filter(models.BitacoraError.origen_id.in_(ids)).all()
        }
        for fila in seccion.upsert:
            datos = fila.model_dump()
            obj = existentes.get(fila.origen_id)
            if obj is None:
                obj = models.BitacoraError(**datos)
                db.add(obj)
                existentes[fila.origen_id] = obj
                insertadas += 1
            else:
                for k, v in datos.items():
                    setattr(obj, k, v)
                actualizadas += 1
        db.flush()

    eliminadas = 0
    if seccion.vigentes is not None:
        eliminadas = _eliminar_bitacora_no_vigente(db, seccion.vigentes)
    return schemas.BitacoraOut(insertadas=insertadas, actualizadas=actualizadas, eliminadas=eliminadas)


def _eliminar_bitacora_no_vigente(db: Session, vigentes: schemas.BitacoraVigentesIn) -> int:
    """Borra las filas reflejadas (origen_id no nulo) con fecha_hora desde
    `vigentes.desde` cuyo origen_id no este en la lista. Se compara en
    Python (la lista puede tener decenas de miles de ids) y se borra por
    lotes de ids locales."""
    desde = datetime.combine(vigentes.desde, datetime.min.time())
    ids_vigentes = set(vigentes.ids)
    locales = (
        db.query(models.BitacoraError.id, models.BitacoraError.origen_id)
        .filter(models.BitacoraError.origen_id.isnot(None), models.BitacoraError.fecha_hora >= desde)
        .all()
    )
    sobrantes = [id_ for id_, origen_id in locales if origen_id not in ids_vigentes]
    if sobrantes and _envio_sospechosamente_chico(len(locales) - len(sobrantes), len(locales)):
        # La lista vigente cubre menos de la mitad de lo que hay en la
        # ventana: viene de una base distinta o a medias. No se borra nada.
        logger.warning(
            "bitacora: lista vigente desde %s con %s ids contra %s filas reflejadas: no se borra nada",
            vigentes.desde, len(ids_vigentes), len(locales),
        )
        return 0
    for i in range(0, len(sobrantes), 500):
        lote = sobrantes[i : i + 500]
        db.query(models.BitacoraError).filter(models.BitacoraError.id.in_(lote)).delete(synchronize_session=False)
    if sobrantes:
        db.flush()
    return len(sobrantes)


def _aplicar_relaciones(db: Session, seccion: schemas.RelacionesIn, completo: bool) -> schemas.CatalogoSeccionOut:
    """dataops_proceso_tabla por id de MySQL. En un envio completo, lo que
    no venga se elimina (la tabla es chica, ~cientos de filas)."""
    ids = [f.id for f in seccion.upsert]
    existentes = {}
    if ids:
        existentes = {r.id: r for r in db.query(models.ProcesoTabla).filter(models.ProcesoTabla.id.in_(ids)).all()}
    insertadas = actualizadas = 0
    for fila in seccion.upsert:
        datos = fila.model_dump()
        obj = existentes.get(fila.id)
        if obj is None:
            db.add(models.ProcesoTabla(**datos))
            insertadas += 1
        else:
            for k, v in datos.items():
                setattr(obj, k, v)
            actualizadas += 1
    db.flush()
    eliminadas = 0
    advertencia = None
    if completo:
        total = db.query(func.count(models.ProcesoTabla.id)).scalar() or 0
        if _envio_sospechosamente_chico(len(ids), total):
            advertencia = f"completo con {len(ids)} relaciones contra {total} existentes: no se borra nada"
            logger.warning("dataops_proceso_tabla: %s", advertencia)
        else:
            consulta = db.query(models.ProcesoTabla)
            if ids:
                consulta = consulta.filter(models.ProcesoTabla.id.notin_(ids))
            eliminadas = consulta.delete(synchronize_session=False)
    return schemas.CatalogoSeccionOut(
        insertadas=insertadas, actualizadas=actualizadas, eliminadas=eliminadas, omitidas=0, advertencia=advertencia
    )


def filtro_bitacora_local_automatica():
    """Episodios de proceso/tabla que la app genero por su cuenta (poller
    viejo): sin origen_id, sin autor humano y que no son incoherencias.
    Desde que la bitacora se replica de MySQL son duplicados."""
    from sqlalchemy import and_, or_

    return and_(
        models.BitacoraError.origen_id.is_(None),
        models.BitacoraError.creado_por_id.is_(None),
        or_(models.BitacoraError.estado.is_(None), models.BitacoraError.estado != "INCOHERENCIA"),
    )


def eliminar_bitacora_local_automatica(db: Session) -> int:
    """Borra los episodios locales automaticos (ver filtro). Las entradas
    manuales y las incoherencias se conservan."""
    borradas = db.query(models.BitacoraError).filter(filtro_bitacora_local_automatica()).delete(synchronize_session=False)
    db.commit()
    return borradas


def estado_catalogos(db: Session, hoy) -> schemas.CatalogoEstadoOut:
    """Resumen de lo recibido, para verificar contra MySQL de OP_PROD sin
    entrar a la base ni a los logs del hosting."""
    from sqlalchemy import func

    def _cuenta_y_max(modelo, columna_fecha, columna_ts):
        return db.query(func.count(modelo.id), func.max(columna_ts)).filter(columna_fecha == hoy).one()

    procesos, ts_procesos = _cuenta_y_max(models.Control, models.Control.snapshot_fecha, models.Control.snapshot_ts)
    tablas, ts_tablas = _cuenta_y_max(models.Tabla, models.Tabla.snapshot_fecha, models.Tabla.snapshot_ts)
    eventos, ultimo_evento_ts, ultimo_evento_id = (
        db.query(func.count(models.CatalogoCambio.id), func.max(models.CatalogoCambio.ts), func.max(models.CatalogoCambio.id))
        .filter(func.date(models.CatalogoCambio.ts) == hoy)
        .one()
    )
    cursor = db.query(models.PollerState).first()
    abiertos = db.query(func.count(models.EpisodioAlerta.id)).filter(models.EpisodioAlerta.abierto.is_(True)).scalar()
    bitacora_total, bitacora_ultima = (
        db.query(
            func.count(models.BitacoraError.id),
            func.max(func.coalesce(models.BitacoraError.fecha_actualizacion, models.BitacoraError.fecha_hora)),
        )
        .filter(models.BitacoraError.origen_id.isnot(None))
        .one()
    )
    locales = db.query(func.count(models.BitacoraError.id)).filter(models.BitacoraError.origen_id.is_(None)).scalar()
    locales_auto = db.query(func.count(models.BitacoraError.id)).filter(filtro_bitacora_local_automatica()).scalar()
    hoy_mysql = (
        db.query(func.count(models.BitacoraError.id))
        .filter(models.BitacoraError.origen_id.isnot(None), func.date(models.BitacoraError.fecha_hora) == hoy)
        .scalar()
    )
    return schemas.CatalogoEstadoOut(
        bitacora_total=bitacora_total,
        bitacora_ultima_actualizacion=bitacora_ultima,
        bitacora_locales=locales or 0,
        bitacora_locales_automaticas=locales_auto or 0,
        bitacora_hoy_mysql=hoy_mysql or 0,
        relaciones_total=db.query(func.count(models.ProcesoTabla.id)).scalar() or 0,
        usuarios_total=db.query(func.count(models.Usuario.id)).scalar() or 0,
        fecha=hoy,
        procesos_hoy=procesos,
        tablas_hoy=tablas,
        eventos_hoy=eventos,
        ultimo_snapshot_ts=max(t for t in (ts_procesos, ts_tablas) if t is not None) if (ts_procesos or ts_tablas) else None,
        ultimo_evento_ts=ultimo_evento_ts,
        ultimo_evento_id=ultimo_evento_id or 0,
        ultimo_cambio_revisado=cursor.ultimo_cambio_revisado if cursor else 0,
        episodios_alerta_abiertos=abiertos or 0,
    )


def aplicar_push_catalogos(db: Session, push: schemas.CatalogoPushIn) -> schemas.CatalogoPushOut:
    """Aplica un envio de OP_PROD en una sola transaccion: o entra todo o no
    entra nada, para que un reintento parcial nunca deje los catalogos a
    medias respecto de los eventos."""
    try:
        procesos = _aplicar_catalogo(db, models.Control, push.procesos, push.fecha, push.completo)
        tablas = _aplicar_catalogo(db, models.Tabla, push.tablas, push.fecha, push.completo)
        eventos = _aplicar_eventos(db, push.eventos)
        usuarios = _aplicar_usuarios(db, push.usuarios) if push.usuarios is not None else None
        bitacora = _aplicar_bitacora(db, push.bitacora) if push.bitacora is not None else None
        relaciones = (
            _aplicar_relaciones(db, push.relaciones, push.completo) if push.relaciones is not None else None
        )
        db.commit()
    except Exception:
        db.rollback()
        raise

    resultado = schemas.CatalogoPushOut(
        procesos=procesos, tablas=tablas, eventos=eventos, usuarios=usuarios, bitacora=bitacora, relaciones=relaciones
    )
    logger.info(
        "Catalogos recibidos de OP_PROD (fecha %s, completo=%s): %s",
        push.fecha, push.completo, resultado.model_dump(),
    )
    return resultado
