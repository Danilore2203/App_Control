class Control {
  final int id;
  final String nombre;
  final String fuente;
  final String estado;
  final String color;
  final String? horaProgramada;
  final String? horaLog;
  final String? horaFin;
  final String? core;
  final String? ruta;
  final String? version;
  final DateTime snapshotFecha;
  final DateTime snapshotTs;

  Control({
    required this.id,
    required this.nombre,
    required this.fuente,
    required this.estado,
    required this.color,
    required this.snapshotFecha,
    required this.snapshotTs,
    this.horaProgramada,
    this.horaLog,
    this.horaFin,
    this.core,
    this.ruta,
    this.version,
  });

  factory Control.fromJson(Map<String, dynamic> json) {
    return Control(
      id: json["id"],
      nombre: json["nombre"],
      fuente: json["fuente"],
      estado: json["estado"],
      color: json["color"],
      horaProgramada: json["hora_programada"],
      horaLog: json["hora_log"],
      horaFin: json["hora_fin"],
      core: json["core"],
      ruta: json["ruta"],
      version: json["version"],
      snapshotFecha: DateTime.parse(json["snapshot_fecha"]),
      snapshotTs: DateTime.parse(json["snapshot_ts"]),
    );
  }

  /// El backend reclasifica un DEMORADO (ya paso su hora_fin) como color
  /// "red" para tratarlo como falla real -nunca llega un control con color
  /// "orange" crudo-, asi que hay que distinguirlo por estado para no
  /// mostrarlo visualmente igual que un error duro.
  bool get esDemorado => color == "red" && estado.toUpperCase() == "DEMORADO";
}
