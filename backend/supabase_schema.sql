CREATE TABLE dataops_catalogo_procesos (
	id SERIAL NOT NULL, 
	nombre VARCHAR(255) NOT NULL, 
	fuente VARCHAR(20) NOT NULL, 
	estado VARCHAR(50) NOT NULL, 
	color VARCHAR(20) NOT NULL, 
	hora_programada VARCHAR(20), 
	hora_log VARCHAR(30), 
	hora_fin VARCHAR(30), 
	core VARCHAR(10), 
	ruta VARCHAR(500), 
	version VARCHAR(100), 
	snapshot_fecha DATE NOT NULL, 
	snapshot_ts TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);

CREATE TABLE dataops_catalogo_tablas (
	id SERIAL NOT NULL, 
	nombre VARCHAR(255) NOT NULL, 
	fuente VARCHAR(20) NOT NULL, 
	estado VARCHAR(50) NOT NULL, 
	color VARCHAR(20) NOT NULL, 
	cantidad INTEGER NOT NULL, 
	layer VARCHAR(30), 
	hora_programada VARCHAR(20), 
	ultima_fecha VARCHAR(30), 
	snapshot_fecha DATE NOT NULL, 
	snapshot_ts TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
);

CREATE TABLE dataops_proceso_tabla (
	id SERIAL NOT NULL, 
	proceso_nombre VARCHAR(255) NOT NULL, 
	tabla_nombre VARCHAR(255) NOT NULL, 
	tipo_relacion VARCHAR(20) NOT NULL, 
	orden INTEGER NOT NULL, 
	activo BOOLEAN NOT NULL, 
	creado_en TIMESTAMP WITHOUT TIME ZONE, 
	auto_inferida BOOLEAN NOT NULL, 
	PRIMARY KEY (id)
);

CREATE TABLE poller_state (
	id SERIAL NOT NULL, 
	ultimo_id_revisado INTEGER NOT NULL, 
	ultimo_id_tablas_revisado INTEGER NOT NULL, 
	PRIMARY KEY (id)
);

CREATE TABLE solicitudes_acceso_google (
	id SERIAL NOT NULL, 
	email VARCHAR(150) NOT NULL, 
	nombre VARCHAR(150), 
	estado VARCHAR(20) NOT NULL, 
	creado_en TIMESTAMP WITHOUT TIME ZONE, 
	PRIMARY KEY (id), 
	UNIQUE (email)
);

CREATE TABLE usuarios (
	id SERIAL NOT NULL, 
	username VARCHAR(100) NOT NULL, 
	nombre VARCHAR(150), 
	email VARCHAR(150), 
	password_hash VARCHAR(255), 
	activo BOOLEAN, 
	fecha_creacion TIMESTAMP WITHOUT TIME ZONE, 
	PRIMARY KEY (id)
);

CREATE TABLE administradores (
	id SERIAL NOT NULL, 
	usuario_id INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	UNIQUE (usuario_id), 
	FOREIGN KEY(usuario_id) REFERENCES usuarios (id)
);

CREATE TABLE alertas (
	id SERIAL NOT NULL, 
	control_id INTEGER NOT NULL, 
	usuario_id INTEGER, 
	mensaje VARCHAR(500) NOT NULL, 
	nivel VARCHAR(20) NOT NULL, 
	enviada BOOLEAN, 
	creado_en TIMESTAMP WITHOUT TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(control_id) REFERENCES dataops_catalogo_procesos (id), 
	FOREIGN KEY(usuario_id) REFERENCES usuarios (id)
);

CREATE TABLE bitacora_errores (
	id SERIAL NOT NULL, 
	fecha_hora TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
	fecha_actualizacion TIMESTAMP WITHOUT TIME ZONE, 
	nombre VARCHAR(255) NOT NULL, 
	tecnologia VARCHAR(30) NOT NULL, 
	descripcion VARCHAR(1000) NOT NULL, 
	creado_por_id INTEGER, 
	"Estado" VARCHAR(30), 
	"Estado_Fin" VARCHAR(30), 
	"Tipo" VARCHAR(150), 
	PRIMARY KEY (id), 
	FOREIGN KEY(creado_por_id) REFERENCES usuarios (id)
);

CREATE TABLE usuarios_fcm_tokens (
	id SERIAL NOT NULL, 
	usuario_id INTEGER NOT NULL, 
	fcm_token VARCHAR(512) NOT NULL, 
	actualizado_en TIMESTAMP WITHOUT TIME ZONE, 
	PRIMARY KEY (id), 
	UNIQUE (usuario_id), 
	FOREIGN KEY(usuario_id) REFERENCES usuarios (id)
);

