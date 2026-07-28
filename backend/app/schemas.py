import re
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator


class UsuarioCreate(BaseModel):
    username: str = Field(pattern=r"^[A-Za-z][A-Za-z0-9_.]{2,99}$")
    password: str
    nombre: Optional[str] = None
    email: Optional[EmailStr] = None


class UsuarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    nombre: Optional[str] = None
    email: Optional[str] = None
    activo: bool
    es_admin: bool = False


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    infra_token: Optional[str] = None


class GoogleLoginIn(BaseModel):
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
    def _requiere_alguna_verificacion(self) -> "ConfigurarPasswordIn":
        if not self.password_actual and not self.correo_verificacion:
            raise ValueError("Debes indicar tu contrasena actual o tu correo de verificacion")
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
ESTADOS_PROCESO = {"ERROR"}
ESTADOS_TABLA = {"VACIA", "ERROR", "DATOS_INCORRECTOS"}


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


class BitacoraResumenMesOut(BaseModel):
    mes: int
    total: int
    tiene_error: bool


class BitacoraResumenAnioOut(BaseModel):
    anio: int
    total_anual: int
    variacion_pct: Optional[float] = None
    meses: list[BitacoraResumenMesOut]
