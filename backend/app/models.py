from datetime import datetime

from sqlalchemy import BigInteger, Boolean, Column, Date, DateTime, ForeignKey, Index, Integer, String, UniqueConstraint
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
    # Ultimo hash que mando la web (push de usuarios). Propio de esta app:
    # sirve para tomar el de la web solo cuando cambia alla, y no pisar
    # todos los dias una contrasena que el usuario cambio aca.
    password_hash_web = Column(String(255), nullable=True)
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
    # Soporta la consulta de "ultimo snapshot por (nombre, fuente)" que hace
    # listar_controles: sin este indice, Postgres tiene que escanear toda la
    # tabla historica para agrupar y de nuevo para el join, y con la tabla ya
    # crecida eso supera el statement_timeout.
    __table_args__ = (
        Index(
            "ix_dataops_catalogo_procesos_nombre_fuente_snapshot_ts",
            "nombre",
            "fuente",
            "snapshot_ts",
        ),
    )

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
    # Hora en que la fila cambio por ultima vez (cualquier columna).
    snapshot_ts = Column(DateTime, nullable=False)
    # Hora en que cambio el ESTADO por ultima vez. Es la que debe usarse para
    # mostrar "en error desde las HH:MM": snapshot_ts tambien se mueve por
    # cambios de hora_log/hora_fin que no son un cambio de estado.
    estado_ts = Column(DateTime, nullable=True)

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
    # 'SI' si es una tabla core (zbx.qa_tablas.CORE en OP_PROD, modal «Tablas core» de la web).
    core = Column(String(10), nullable=True)
    snapshot_fecha = Column(Date, nullable=False)
    snapshot_ts = Column(DateTime, nullable=False)
    estado_ts = Column(DateTime, nullable=True)


class CatalogoCambio(Base):
    """Un evento por cada cambio de estado de un proceso o tabla, tal como lo
    registra OP_PROD en c137.dataops_catalogo_cambios (mismo id). Desde que
    los catalogos se actualizan en el lugar (una fila por nombre y dia, con
    id estable), esta es la unica tabla donde "aparece algo nuevo" cuando un
    proceso cambia: es la que debe recorrer el poller por cursor de id, no
    los catalogos."""

    __tablename__ = "dataops_catalogo_cambios"
    __table_args__ = (Index("ix_dataops_catalogo_cambios_ts", "ts"),)

    id = Column(Integer, primary_key=True)
    tipo = Column(String(10), nullable=False)  # PROCESO | TABLA
    nombre = Column(String(255), nullable=False)
    fuente = Column(String(20), nullable=False, default="")
    estado_anterior = Column(String(50), nullable=True)  # None = aparecio durante el dia
    estado_nuevo = Column(String(50), nullable=False)
    color_nuevo = Column(String(20), nullable=False, default="gray")
    ts = Column(DateTime, nullable=False)


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
    # "web": viene de la lista de administradores del monitor web (push de
    # usuarios) y se quita cuando alla deja de serlo. "app": designado aca a
    # proposito (/internal/administradores); el push no lo toca. NULL: de
    # antes de esta columna; si aparece en la lista de la web pasa a "web".
    origen = Column(String(10), nullable=True)


class BitacoraError(Base):
    """Registro manual de errores: procesos (AIRFLOW/DATASTAGE/PENTAHO) o
    tablas (QA_CONTROL/PG_PROD). Tabla propia de la app."""

    __tablename__ = "bitacora_errores"

    id = Column(Integer, primary_key=True, index=True)
    # id de la misma fila en c137.bitacora_errores de MySQL (la bitacora del
    # monitor web, que OP_PROD replica aca en cada push). NULL = entrada
    # propia de la app: manual, o incoherencia proceso/tabla detectada por el
    # poller. Es la clave del upsert, por eso es unica.
    origen_id = Column(Integer, nullable=True, unique=True, index=True)
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
    # Cursores viejos sobre los catalogos (id > ultimo). Ya no se usan: desde
    # que OP_PROD actualiza las filas en el lugar, un cambio de estado no
    # genera una fila nueva en el catalogo, sino un evento en
    # dataops_catalogo_cambios. Se conservan solo para no alterar la tabla.
    ultimo_id_revisado = Column(Integer, nullable=False, default=0)
    ultimo_id_tablas_revisado = Column(Integer, nullable=False, default=0)
    # Cursor actual: ultimo id de dataops_catalogo_cambios ya volcado a la
    # bitacora. Columna aparte (y no reusar ultimo_id_revisado) porque ese
    # guarda un id de catalogo, que es un numero mucho mayor: reutilizarlo
    # habria saltado todos los eventos.
    ultimo_cambio_revisado = Column(Integer, nullable=False, default=0)


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


class AirflowEstado(Base):
    """Ultima corrida de cada DAG, tal como la ve el Monitor Airflow de OP
    (dag_id -> last_state/is_paused), empujada aparte del catalogo. El
    catalogo que manda el servidor puede clasificar un DAG pausado como
    PAUSADO aunque su ultima corrida haya sido OK; con esto /controles lo
    muestra como el monitor web (OK/ERROR/RUNNING) sin depender de que el
    servidor tenga esa regla. Se ignora si quedo vieja (ver
    services/procesos.py)."""

    __tablename__ = "airflow_estados"

    dag_id = Column(String(250), primary_key=True)
    last_state = Column(String(30), nullable=True)
    is_paused = Column(Boolean, nullable=False, default=False)
    actualizado_en = Column(DateTime, nullable=False)


class Comando(Base):
    """Pedido de la app para que OP_PROD haga algo adentro de la red (ver
    services/comandos.py): consultar sesiones de Netezza/PostgreSQL, lanzar
    un proceso, pausar un DAG, actualizar todos, cancelar una sesion. Render
    no llega al servidor OP (red interna), asi que la app deja el comando aca
    y OP_PROD lo retira por HTTPS cada pocos segundos, lo ejecuta y deja el
    resultado. `payload` y `resultado` son JSON en texto."""

    __tablename__ = "comandos"
    __table_args__ = (Index("ix_comandos_estado_creado", "estado", "creado_en"),)

    id = Column(Integer, primary_key=True, index=True)
    tipo = Column(String(60), nullable=False)
    payload = Column(String, nullable=False, default="{}")
    # pendiente -> en_curso -> ok | error ; o expirado si nadie lo retiro a tiempo
    estado = Column(String(20), nullable=False, default="pendiente", index=True)
    creado_por_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    creado_en = Column(DateTime, nullable=False, default=datetime.utcnow)
    tomado_en = Column(DateTime, nullable=True)
    terminado_en = Column(DateTime, nullable=True)
    resultado = Column(String, nullable=True)
    error = Column(String(2000), nullable=True)
    # Veces que una copia de OP_PROD lo devolvio por no conocerlo (vieja o sin
    # reiniciar). Vuelve a la cola y ya solo lo recibe una copia que diga que
    # sabe hacerlo (ver services/comandos.tomar_pendientes).
    rechazos = Column(Integer, nullable=False, default=0)
    # Que copia de OP_PROD lo retiro (ver EquipoOp.nombre).
    tomado_por = Column(String(120), nullable=True)

    creado_por = relationship("Usuario", lazy="joined")


class EquipoOp(Base):
    """Cada copia de OP_PROD que retira comandos. Solo el servidor .150 puede
    entrar a PostgreSQL PROD, pero cualquier PC con OP abierto como primaria
    (o con OP_APP_CONTROL_COMANDOS=1) tambien consulta la cola; esta tabla
    permite entregarle los comandos a una sola (ver services/comandos.py)."""

    __tablename__ = "op_equipos"

    # X-OP-Equipo (nombre de la PC) si OP lo manda; si no, «IP · user-agent».
    nombre = Column(String(120), primary_key=True)
    identificado = Column(Boolean, nullable=False, default=False)
    activo_desde = Column(DateTime, nullable=False)
    visto_en = Column(DateTime, nullable=False)
    # Fallo al conectar a PostgreSQL (no esta en pg_hba.conf): hasta entonces
    # no se le dan esos comandos si hay otra copia atendiendo.
    sin_pg_hasta = Column(DateTime, nullable=True)


class AlertaInfra(Base):
    """Alarma de infraestructura que no es de un proceso (p.ej. congestion en
    Netezza): la detecta OP_PROD y la avisa por /internal/alertas/infra. Una
    fila por clave; `abierta` mientras dure (ver services/alertas_infra.py)."""

    __tablename__ = "alertas_infra"

    clave = Column(String(60), primary_key=True)
    abierta = Column(Boolean, nullable=False, default=False)
    titulo = Column(String(200), nullable=True)
    mensaje = Column(String(1000), nullable=True)
    abierta_en = Column(DateTime, nullable=True)
    cerrada_en = Column(DateTime, nullable=True)
    actualizada_en = Column(DateTime, nullable=True)
    ultimo_aviso_en = Column(DateTime, nullable=True)


class AlertaInfraEvento(Base):
    """Historial de esas alarmas: cuando abrio, los recordatorios y cuando cerro."""

    __tablename__ = "alertas_infra_eventos"

    id = Column(Integer, primary_key=True, index=True)
    clave = Column(String(60), nullable=False, index=True)
    tipo = Column(String(10), nullable=False)  # abre | sigue | cierra
    titulo = Column(String(200), nullable=True)
    mensaje = Column(String(1000), nullable=True)
    creado_en = Column(DateTime, nullable=False, default=datetime.utcnow)


class LatidoOp(Base):
    """Ultima vez que OP_PROD retiro comandos y que tipos dijo saber hacer.
    Asi la app puede avisar «el correo va a demorar» si nadie esta atendiendo."""

    __tablename__ = "op_latidos"

    clave = Column(String(40), primary_key=True)
    visto_en = Column(DateTime, nullable=False)
    tipos = Column(String, nullable=False, default="")


class CodigoRecuperacion(Base):
    """Codigo de 6 digitos que se manda por correo para cambiar la contrasena
    sin saber la anterior (ver services/recuperacion.py). Solo se guarda un
    HMAC del codigo, nunca el codigo; vence a los 15 minutos, sirve una sola
    vez y se anula despues de 5 intentos fallidos."""

    __tablename__ = "codigos_recuperacion"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, index=True)
    codigo_hash = Column(String(64), nullable=False)
    creado_en = Column(DateTime, nullable=False, default=datetime.utcnow)
    expira_en = Column(DateTime, nullable=False)
    usado_en = Column(DateTime, nullable=True)
    intentos = Column(Integer, nullable=False, default=0)
    # El comando de la cola que manda este codigo: cuando sale el correo, los
    # 15 minutos empiezan a contar de nuevo (si OP_PROD tardo en mandarlo).
    comando_id = Column(Integer, nullable=True)
