"""
Migracion unica (Fase 3 del plan) de las tablas propias de esta app hacia
Supabase, via su API REST (supabase-py, HTTPS/443) — no via conexion directa
a Postgres, porque la red de Nuevatel bloquea esa salida (5432/6543).

`usuarios` NO esta aca: ya la replica el modulo sync_supabase de OP_PROD
(Fase 2), porque es una tabla compartida con el monitor web.

Preserva los `id` originales (para no romper referencias como
alertas.control_id) e informa cuantas filas quedaron sin migrar por
violar una FK (p.ej. alertas viejas que apuntan a un proceso ya podado
del catalogo real).
"""
import os
from datetime import date, datetime

from sqlalchemy import inspect as sa_inspect
from supabase import create_client

from app.database import SessionLocal
from app import models

# Definir antes de correr este script (no hardcodear claves aca):
#   set SUPABASE_URL=https://yqmrtrixsiidrpfmfdza.supabase.co
#   set SUPABASE_SECRET_KEY=sb_secret_...
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SECRET_KEY = os.environ["SUPABASE_SECRET_KEY"]

LOTE = 500

# Orden importa: primero las que no dependen de nadie, despues las que
# tienen FK hacia otra de esta misma lista o hacia usuarios/procesos
# (ya sincronizados por OP_PROD).
TABLAS = [
    ("poller_state", models.PollerState),
    ("solicitudes_acceso_google", models.SolicitudAccesoGoogle),
    ("administradores", models.Administrador),
    ("alertas", models.Alerta),
    ("bitacora_errores", models.BitacoraError),
    ("usuarios_fcm_tokens", models.UsuarioFcmToken),
]


def _fila_a_dict(modelo) -> dict:
    """Usa el mapper de SQLAlchemy para traducir atributo Python -> nombre real
    de columna (necesario para Estado/Estado_Fin/Tipo, con mayusculas propias
    distintas al atributo Python estado/estado_fin/tipo)."""
    fila = {}
    mapper = sa_inspect(type(modelo))
    for attr in mapper.column_attrs:
        columna_db = attr.columns[0].name
        valor = getattr(modelo, attr.key)
        if isinstance(valor, (datetime, date)):
            valor = valor.isoformat()
        fila[columna_db] = valor
    return fila


def migrar_tabla(sb, db, nombre_tabla: str, clase_modelo) -> None:
    filas_orm = db.query(clase_modelo).order_by(clase_modelo.id.asc()).all()
    total = len(filas_orm)
    if total == 0:
        print(f"{nombre_tabla}: 0 filas, nada que migrar")
        return

    migradas = 0
    fallidas = 0
    for inicio in range(0, total, LOTE):
        lote_filas = [_fila_a_dict(m) for m in filas_orm[inicio:inicio + LOTE]]
        try:
            sb.table(nombre_tabla).upsert(lote_filas, on_conflict="id").execute()
            migradas += len(lote_filas)
        except Exception:
            # Una fila del lote seguramente rompe una FK (p.ej. referencia a un
            # proceso ya podado); reintentar una por una para no perder el resto.
            for fila in lote_filas:
                try:
                    sb.table(nombre_tabla).upsert([fila], on_conflict="id").execute()
                    migradas += 1
                except Exception as exc:
                    fallidas += 1
                    print(f"  {nombre_tabla} id={fila.get('id')}: omitida ({exc})")

    print(f"{nombre_tabla}: {migradas}/{total} migradas, {fallidas} omitidas")


def main() -> None:
    sb = create_client(SUPABASE_URL, SUPABASE_SECRET_KEY)
    db = SessionLocal()
    try:
        for nombre_tabla, clase_modelo in TABLAS:
            migrar_tabla(sb, db, nombre_tabla, clase_modelo)
    finally:
        db.close()


if __name__ == "__main__":
    main()
