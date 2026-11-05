import re
from datetime import date, datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator


class UsuarioCreate(BaseModel):
    username: str = Field(pattern=r"^[A-Za-z][A-Za-z0-9_.]{2,99}$")
    password: str = Field(min_length=8)
    nombre: Optional[str] = None
    email: Optional[EmailStr] = None

    @field_validator("password")
    @classmethod
    def validar_fortaleza(cls, valor: str) -> str:
        if not re.search(r"\d", valor):
            raise ValueError("La contrasena debe incluir al menos un numero")
        if not re.search(r"[^A-Za-z0-9]", valor):
            raise ValueError("La contrasena debe incluir al menos un simbolo")
        return valor


class MensajeOut(BaseModel):
    ok: bool
    mensaje: str


class UsuarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    nombre: Optional[str] = None
    email: Optional[str] = None
    email_google: Optional[str] = None
    activo: bool
    es_admin: bool = False


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    infra_token: Optional[str] = None
    refresh_token: Optional[str] = None


class RefreshIn(BaseModel):
    refresh_token: str


class GoogleLoginIn(BaseModel):
    id_token: str


class VincularGoogleIn(BaseModel):
    id_token: str


class ConfigurarPasswordIn(BaseModel):
    username: str
    password_actual: Optional[str] = None
    correo_verificacion: Optional[str] = None
    password_nueva: str = Field(min_length=8)

    @field_validator("password_nueva")
    @classmethod
    def validar_fortaleza(cls, valor: str) -> str:
        if not re.search(r"\d", valor):
            raise ValueError("La contrasena debe incluir al menos un numero")
        if not re.search(r"[^A-Za-z0-9]", valor):
            raise ValueError("La contrasena debe incluir al menos un simbolo")
        return valor

    @model_validator(mode="after")
    def _requiere_password_actual(self) -> "ConfigurarPasswordIn":
        # correo_verificacion se acepta por compatibilidad con la app, pero
        # ya no verifica nada (ver auth.configurar_password_local).
        if not self.password_actual:
            raise ValueError(
                "Debes indicar tu contrasena actual. Si todavia no tienes una, entra con Google "
                "o pide a un administrador que te asigne una."
            )
        return self


class FcmTokenIn(BaseModel):
    fcm_token: str


class SolicitudAccesoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    nombre: Optional[str] = None
    estado: str
    creado_en: datetime


class SolicitudRegistroOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    email: Optional[str] = None
    nombre: Optional[str] = None
    estado: str
    creado_en: datetime


class ControlOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    nombre: str
    fuente: str
    estado: str
    color: str
    hora_programada: Optional[str] = None
    hora_log: Optional[str] = None
    hora_fin: Optional[str] = None
    core: Optional[str] = None
    ruta: Optional[str] = None
    version: Optional[str] = None
    snapshot_fecha: date
    snapshot_ts: datetime
    estado_ts: Optional[datetime] = None  # hora real del ultimo cambio de estado


class HistorialFallaOut(BaseModel):
    fecha: date
    fallas: int


class AlertaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    control_id: int
    mensaje: str
    nivel: str
    enviada: bool
    creado_en: datetime


TECNOLOGIAS_PROCESO = {"AIRFLOW", "DATASTAGE", "PENTAHO"}
TECNOLOGIAS_TABLA = {"QA_CONTROL", "PG_PROD"}

CATEGORIAS_MANUALES = {"RESUELTO", "ADVERTENCIA", "INFORMACION", "REINTENTO", "EJECUTADO"}
ESTADOS_PROCESO = {"ERROR", "DEMORADO"} | CATEGORIAS_MANUALES
ESTADOS_TABLA = {"VACIA", "ERROR", "DATOS_INCORRECTOS"} | CATEGORIAS_MANUALES

SISTEMAS_LEGIBLES = {
    "AIRFLOW": "Airflow",
    "DATASTAGE": "DataStage",
    "PENTAHO": "Pentaho",
    "QA_CONTROL": "QA Control",
    "PG_PROD": "PostgreSQL Producción",
}


class BitacoraErrorIn(BaseModel):
    nombre: str = Field(min_length=1, max_length=255)
    tecnologia: str
    estado: str
    descripcion: str = Field(min_length=1, max_length=1000)
    fecha_hora: Optional[datetime] = None

    @field_validator("tecnologia")
    @classmethod
    def _tecnologia_valida(cls, valor: str) -> str:
        valor = valor.upper().strip()
        if valor not in TECNOLOGIAS_PROCESO | TECNOLOGIAS_TABLA:
            raise ValueError(
                "tecnologia debe ser una de: " + ", ".join(sorted(TECNOLOGIAS_PROCESO | TECNOLOGIAS_TABLA))
            )
        return valor

    @model_validator(mode="after")
    def _estado_valido_para_tecnologia(self) -> "BitacoraErrorIn":
        self.estado = self.estado.upper().strip()
        estados_validos = ESTADOS_PROCESO if self.tecnologia in TECNOLOGIAS_PROCESO else ESTADOS_TABLA
        if self.estado not in estados_validos:
            raise ValueError(
                f"Para {self.tecnologia} el estado debe ser una de: " + ", ".join(sorted(estados_validos))
            )
        return self


def tipo_para_tecnologia(tecnologia: str) -> str:
    return "PROCESO" if tecnologia in TECNOLOGIAS_PROCESO else "TABLA"


class BitacoraErrorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    fecha_hora: datetime
    fecha_actualizacion: Optional[datetime] = None
    nombre: str
    tecnologia: str
    estado: Optional[str] = None
    estado_fin: Optional[str] = None
    tipo: Optional[str] = None
    descripcion: str
    creado_por_id: Optional[int] = Field(default=None, exclude=True)

    duracion_segundos: Optional[int] = None
    sistema: Optional[str] = None
    origen: Optional[str] = None

    @model_validator(mode="after")
    def _calcular_campos_derivados(self) -> "BitacoraErrorOut":
        self.sistema = SISTEMAS_LEGIBLES.get(self.tecnologia, self.tecnologia)
        self.origen = "Manual" if self.creado_por_id is not None else "Automático"
        if self.estado_fin == "OK" and self.fecha_actualizacion is not None:
            self.duracion_segundos = int((self.fecha_actualizacion - self.fecha_hora).total_seconds())
        return self


class BitacoraResumenMesOut(BaseModel):
    mes: int
    total: int
    tiene_error: bool
    abiertos: int = 0  # episodios de ese mes que siguen sin resolver


class BitacoraResumenAnioOut(BaseModel):
    anio: int
    total_anual: int
    variacion_pct: Optional[float] = None
    meses: list[BitacoraResumenMesOut]
    # Indicadores del momento (no dependen del anio consultado), para la
    # cabecera de la bitacora: lo que importa hoy, no el acumulado del anio.
    abiertos_ahora: int = 0
    hoy: int = 0
    ultimos_7_dias: int = 0


# ---- Catalogos empujados por OP_PROD (POST /internal/catalogos) ----
# Los ids son los de MySQL (c137.*): OP_PROD los manda tal cual y aca se
# conservan, para que alertas.control_id y los cursores del poller sigan
# apuntando a lo mismo en los dos lados.


class CatalogoProcesoIn(BaseModel):
    id: int
    nombre: str
    fuente: str
    estado: str
    color: str
    hora_programada: Optional[str] = None
    hora_log: Optional[str] = None
    hora_fin: Optional[str] = None
    core: Optional[str] = None
    ruta: Optional[str] = None
    version: Optional[str] = None
    snapshot_fecha: date
    snapshot_ts: datetime
    estado_ts: Optional[datetime] = None


class CatalogoTablaIn(BaseModel):
    id: int
    nombre: str
    fuente: str
    estado: str
    color: str
    cantidad: int = 0
    layer: Optional[str] = None
    hora_programada: Optional[str] = None
    ultima_fecha: Optional[str] = None
    snapshot_fecha: date
    snapshot_ts: datetime
    estado_ts: Optional[datetime] = None


class CatalogoEventoIn(BaseModel):
    id: int
    tipo: Literal["PROCESO", "TABLA"]
    nombre: str
    fuente: str = ""
    estado_anterior: Optional[str] = None  # None = aparecio durante el dia
    estado_nuevo: str
    color_nuevo: str = "gray"
    ts: datetime


class CatalogoProcesosIn(BaseModel):
    upsert: list[CatalogoProcesoIn] = Field(default_factory=list)
    bajas: list[int] = Field(default_factory=list)


class CatalogoTablasIn(BaseModel):
    upsert: list[CatalogoTablaIn] = Field(default_factory=list)
    bajas: list[int] = Field(default_factory=list)


class UsuarioImportIn(BaseModel):
    """Fila de la tabla usuarios de MySQL (compartida con el monitor web).
    Se identifica por username, no por id: los ids locales los asigna esta
    base (hay usuarios creados aca que no existen alla)."""

    username: str
    nombre: Optional[str] = None
    email: Optional[str] = None
    email_google: Optional[str] = None
    password_hash: Optional[str] = None  # bcrypt, el mismo formato que usa la app
    activo: bool = True
    fecha_creacion: Optional[datetime] = None


class UsuariosIn(BaseModel):
    upsert: list[UsuarioImportIn] = Field(default_factory=list)
    administradores: list[str] = Field(default_factory=list)  # usernames


class BitacoraImportIn(BaseModel):
    """Fila de c137.bitacora_errores (la bitacora del monitor web). Se
    identifica por `origen_id` (el id de MySQL); el id local es propio."""

    origen_id: int
    fecha_hora: datetime
    fecha_actualizacion: Optional[datetime] = None
    nombre: str
    tecnologia: str
    descripcion: str = ""
    estado: Optional[str] = None
    estado_fin: Optional[str] = None
    tipo: Optional[str] = None


class BitacoraIn(BaseModel):
    upsert: list[BitacoraImportIn] = Field(default_factory=list)


class RelacionImportIn(BaseModel):
    """Fila de c137.dataops_proceso_tabla (que tabla alimenta cada proceso),
    usada por el chequeo de fallo silencioso. Mismo id que MySQL."""

    id: int
    proceso_nombre: str
    tabla_nombre: str
    tipo_relacion: str = "ALIMENTA"
    orden: int = 0
    activo: bool = True
    creado_en: Optional[datetime] = None
    auto_inferida: bool = False


class RelacionesIn(BaseModel):
    upsert: list[RelacionImportIn] = Field(default_factory=list)


class CatalogoPushIn(BaseModel):
    """Un ciclo de snapshot de OP_PROD: lo que cambio en los catalogos de
    `fecha` y los eventos de cambio de estado. Con `completo=True` el envio
    trae todas las filas del dia y lo que no venga se elimina.

    Secciones opcionales (MySQL es la fuente, la app solo refleja):
    - `usuarios`: tabla usuarios + administradores (solo en envios completos).
    - `bitacora`: filas nuevas o modificadas de bitacora_errores desde el
      envio anterior (en los completos, los ultimos dias). Upsert por origen_id.
    - `relaciones`: dataops_proceso_tabla completa (solo en envios completos);
      lo que no venga se elimina."""

    fecha: date
    completo: bool = False
    procesos: CatalogoProcesosIn = Field(default_factory=CatalogoProcesosIn)
    tablas: CatalogoTablasIn = Field(default_factory=CatalogoTablasIn)
    eventos: list[CatalogoEventoIn] = Field(default_factory=list)
    usuarios: Optional[UsuariosIn] = None
    bitacora: Optional[BitacoraIn] = None
    relaciones: Optional[RelacionesIn] = None


class CatalogoSeccionOut(BaseModel):
    insertadas: int
    actualizadas: int
    eliminadas: int
    omitidas: int  # bajas que no se borraron por tener alertas asociadas


class CatalogoEventosOut(BaseModel):
    insertados: int
    ignorados: int  # ya existian (reintento del mismo envio)


class UsuariosOut(BaseModel):
    insertados: int
    actualizados: int
    administradores_nuevos: int
    omitidos: list[str]  # usernames cuyo email ya pertenece a otro usuario local


class BitacoraOut(BaseModel):
    insertadas: int
    actualizadas: int


class CatalogoPushOut(BaseModel):
    procesos: CatalogoSeccionOut
    tablas: CatalogoSeccionOut
    eventos: CatalogoEventosOut
    usuarios: Optional[UsuariosOut] = None
    bitacora: Optional[BitacoraOut] = None
    relaciones: Optional[CatalogoSeccionOut] = None


class PasswordAdminIn(BaseModel):
    password: str = Field(min_length=8, max_length=128)


class AdministradorIn(BaseModel):
    """POST /internal/administradores: deja a este correo como administrador
    (creando el usuario si hace falta). Para la primera cuenta de una base
    nueva o para sumar administradores sin tocar la base."""

    email: EmailStr
    nombre: Optional[str] = None


class CatalogoEstadoOut(BaseModel):
    """Que tiene App_Control en su base, para contrastar con MySQL de OP_PROD
    (GET /internal/catalogos/estado)."""

    fecha: date
    procesos_hoy: int
    tablas_hoy: int
    eventos_hoy: int
    ultimo_snapshot_ts: Optional[datetime] = None  # ultima fila de catalogo tocada
    ultimo_evento_ts: Optional[datetime] = None
    ultimo_evento_id: int
    ultimo_cambio_revisado: int  # cursor del poller sobre los eventos
    episodios_alerta_abiertos: int
    bitacora_total: int = 0  # filas replicadas de MySQL (con origen_id)
    bitacora_ultima_actualizacion: Optional[datetime] = None
    # Filas propias de la app (origen_id NULL): manuales e incoherencias...
    bitacora_locales: int = 0
    # ...y las que genero el poller viejo por su cuenta (episodios de
    # proceso/tabla sin autor): duplican a las de MySQL y deben borrarse.
    bitacora_locales_automaticas: int = 0
    bitacora_hoy_mysql: int = 0  # filas de hoy con origen_id
    relaciones_total: int = 0
    usuarios_total: int = 0
