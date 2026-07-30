from datetime import datetime

from sqlalchemy import BigInteger, Boolean, Column, Date, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import relationship

from app.database import Base


class Usuario(Base):
    """Refleja la tabla usuarios real, compartida con el monitor web (mismas cuentas,
    mismo login vía AD). No se crea/altera su estructura, solo se lee/inserta filas."""

    __tablename__ = "usuarios"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(100), unique=True, index=True, nullable=False)
    nombre = Column(String(150), nullable=True)
    email = Column(String(150), nullable=True)
    password_hash = Column(String(255), nullable=True)
    activo = Column(Boolean, default=True)
    fecha_creacion = Column(DateTime, default=datetime.utcnow)
    # Vincula esta cuenta AD con un correo de Google (puede ser distinto al
    # email corporativo). Propio de esta app: no existe en la tabla real de
    # MySQL, asi que el sync de OP_PROD nunca lo toca.
    email_google = Column(String(150), nullable=True)

    alertas = relationship("Alerta", back_populates="usuario")
    fcm_token_row = relationship("UsuarioFcmToken", back_populates="usuario", uselist=False)


class UsuarioFcmToken(Base):
    """Tabla propia (no existe en el monitor web) para guardar el token FCM de cada
    usuario, ya que la tabla usuarios compartida no tiene ese campo."""

    __tablename__ = "usuarios_fcm_tokens"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, unique=True)
    fcm_token = Column(String(512), nullable=False)
    actualizado_en = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    usuario = relationship("Usuario", back_populates="fcm_token_row")


class Control(Base):
    """Refleja la tabla dataops_catalogo_procesos, propiedad del proceso DWH existente
    (no se crea/altera aca, solo se lee). Cada fila es un snapshot historico de un proceso."""

    __tablename__ = "dataops_catalogo_procesos"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(255), nullable=False)
    fuente = Column(String(20), nullable=False)
    estado = Column(String(50), nullable=False)
    color = Column(String(20), nullable=False)
    hora_programada = Column(String(20), nullable=True)
    hora_log = Column(String(30), nullable=True)
    hora_fin = Column(String(30), nullable=True)
    core = Column(String(10), nullable=True)
    ruta = Column(String(500), nullable=True)
    version = Column(String(100), nullable=True)
    snapshot_fecha = Column(Date, nullable=False)
    snapshot_ts = Column(DateTime, nullable=False)

    alertas = relationship("Alerta", back_populates="control")


class Tabla(Base):
    """Refleja la tabla dataops_catalogo_tablas, propiedad del proceso DWH existente
    (no se crea/altera aca, solo se lee). Cada fila es un snapshot historico de una tabla."""

    __tablename__ = "dataops_catalogo_tablas"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(255), nullable=False)
    fuente = Column(String(20), nullable=False)
    estado = Column(String(50), nullable=False)
    color = Column(String(20), nullable=False)
    cantidad = Column(BigInteger, nullable=False)
    layer = Column(String(30), nullable=True)
    hora_programada = Column(String(20), nullable=True)
    ultima_fecha = Column(String(30), nullable=True)
    snapshot_fecha = Column(Date, nullable=False)
    snapshot_ts = Column(DateTime, nullable=False)


class ProcesoTabla(Base):
    """Refleja dataops_proceso_tabla: catalogo real que dice que tabla alimenta
    cada proceso (no se crea/altera aca, solo se lee). Con esto se puede
    revisar, cuando un proceso core termina OK, si su tabla realmente quedo
    con datos coherentes."""

    __tablename__ = "dataops_proceso_tabla"

    id = Column(Integer, primary_key=True, index=True)
    proceso_nombre = Column(String(255), nullable=False)
    tabla_nombre = Column(String(255), nullable=False)
    tipo_relacion = Column(String(20), nullable=False)
    orden = Column(Integer, nullable=False, default=0)
    activo = Column(Boolean, nullable=False, default=True)
    creado_en = Column(DateTime, default=datetime.utcnow)
    auto_inferida = Column(Boolean, nullable=False, default=False)


class Alerta(Base):
    __tablename__ = "alertas"

    id = Column(Integer, primary_key=True, index=True)
    control_id = Column(Integer, ForeignKey("dataops_catalogo_procesos.id"), nullable=False)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    mensaje = Column(String(500), nullable=False)
    nivel = Column(String(20), nullable=False, default="critica")  # critica | normal
    enviada = Column(Boolean, default=False)
    creado_en = Column(DateTime, default=datetime.utcnow)

    control = relationship("Control", back_populates="alertas")
    usuario = relationship("Usuario", back_populates="alertas")


class SolicitudAccesoGoogle(Base):
    """Solicitud de acceso de una cuenta de Google que inicio sesion pero cuyo
    correo no existe (todavia) como usuario. Un administrador la aprueba o
    rechaza; al aprobarla se crea la fila correspondiente en usuarios."""

    __tablename__ = "solicitudes_acceso_google"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(150), unique=True, nullable=False)
    nombre = Column(String(150), nullable=True)
    estado = Column(String(20), nullable=False, default="pendiente")  # pendiente | aprobada | rechazada
    creado_en = Column(DateTime, default=datetime.utcnow)


class SolicitudRegistro(Base):
    """Solicitud de una cuenta local (usuario/contrasena elegidos a mano en
    la app, sin pasar por AD ni Google). Un administrador la aprueba o
    rechaza; al aprobarla recien se crea la fila en usuarios, con el
    password_hash que ya se guardo aca (nunca se guarda en texto plano).
    Tabla propia, no toca la estructura de la tabla usuarios compartida."""

    __tablename__ = "solicitudes_registro"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(100), nullable=False)
    email = Column(String(150), nullable=True)
    nombre = Column(String(150), nullable=True)
    password_hash = Column(String(255), nullable=False)
    estado = Column(String(20), nullable=False, default="pendiente")  # pendiente | aprobada | rechazada
    creado_en = Column(DateTime, default=datetime.utcnow)


class Administrador(Base):
    """Marca que un usuario puede aprobar/rechazar solicitudes de acceso.
    Tabla propia, no toca la estructura de la tabla usuarios compartida."""

    __tablename__ = "administradores"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, unique=True)


class BitacoraError(Base):
    """Registro manual de errores: procesos (AIRFLOW/DATASTAGE/PENTAHO) o
    tablas (QA_CONTROL/PG_PROD). Tabla propia de la app."""

    __tablename__ = "bitacora_errores"

    id = Column(Integer, primary_key=True, index=True)
    fecha_hora = Column(DateTime, nullable=False, default=datetime.utcnow)
    fecha_actualizacion = Column(DateTime, nullable=True)
    nombre = Column(String(255), nullable=False)
    tecnologia = Column(String(30), nullable=False)
    descripcion = Column(String(1000), nullable=False)
    creado_por_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    estado = Column("Estado", String(30), nullable=True)
    estado_fin = Column("Estado_Fin", String(30), nullable=True)
    tipo = Column("Tipo", String(150), nullable=True)


class PollerState(Base):
    """Fila unica que recuerda hasta que id de dataops_catalogo_procesos ya se reviso,
    para no generar alertas repetidas en cada ciclo del poller."""

    __tablename__ = "poller_state"

    id = Column(Integer, primary_key=True)
    ultimo_id_revisado = Column(Integer, nullable=False, default=0)
    ultimo_id_tablas_revisado = Column(Integer, nullable=False, default=0)


class EpisodioAlerta(Base):
    """Estado de alarma de un proceso (nombre+fuente), independiente de si el
    origen escribe filas nuevas o no. Mientras `abierto` sea true el proceso
    sigue en rojo/naranja. Se cierra cuando el proceso vuelve a verde y se
    reabre (como episodio nuevo) si vuelve a fallar despues. Quien ya fue
    notificado con exito para el tramo abierto actual se guarda aparte, en
    EpisodioAlertaUsuario (no alcanza con un solo booleano por episodio: si
    a un destinatario el push le fallo -token vencido- pero a otros les
    llego bien, ese destinatario puntual tiene que seguir reintentando sin
    volver a molestar a los que ya se enteraron)."""

    __tablename__ = "episodios_alerta"
    __table_args__ = (UniqueConstraint("nombre", "fuente", name="uq_episodio_alerta_nombre_fuente"),)

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(255), nullable=False)
    fuente = Column(String(20), nullable=False)
    color = Column(String(20), nullable=False)
    abierto = Column(Boolean, nullable=False, default=True)
    control_id_actual = Column(Integer, nullable=True)
    primera_deteccion = Column(DateTime, nullable=False, default=datetime.utcnow)
    ultima_alerta_en = Column(DateTime, nullable=True)
    cerrado_en = Column(DateTime, nullable=True)

    notificados = relationship(
        "EpisodioAlertaUsuario", cascade="all, delete-orphan", back_populates="episodio"
    )


class EpisodioAlertaUsuario(Base):
    """Un usuario ya fue notificado (push exitoso) para el tramo ACTUALMENTE
    abierto del episodio. Se borra cuando el episodio se cierra o se reabre,
    para que la proxima vez que el proceso falle se le vuelva a avisar a
    todos desde cero."""

    __tablename__ = "episodios_alerta_usuarios"
    __table_args__ = (UniqueConstraint("episodio_id", "usuario_id", name="uq_episodio_alerta_usuario"),)

    id = Column(Integer, primary_key=True, index=True)
    episodio_id = Column(Integer, ForeignKey("episodios_alerta.id"), nullable=False)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    notificado_en = Column(DateTime, nullable=False, default=datetime.utcnow)

    episodio = relationship("EpisodioAlerta", back_populates="notificados")
