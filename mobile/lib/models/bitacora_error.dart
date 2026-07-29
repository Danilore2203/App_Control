const tecnologiasProceso = ["AIRFLOW", "DATASTAGE", "PENTAHO"];
const tecnologiasTabla = ["QA_CONTROL", "PG_PROD"];
const estadosProceso = ["ERROR", "DEMORADO"];
const estadosTabla = ["VACIA", "DATOS_INCORRECTOS"];

class BitacoraError {
  final int id;
  final DateTime fechaHora;
  final DateTime? fechaActualizacion;
  final String nombre;
  final String tecnologia;
  final String? estado;
  final String? estadoFin;
  final String? tipo;
  final String descripcion;

  BitacoraError({
    required this.id,
    required this.fechaHora,
    required this.nombre,
    required this.tecnologia,
    required this.descripcion,
    this.fechaActualizacion,
    this.estado,
    this.estadoFin,
    this.tipo,
  });

  bool get esProceso => tipo != null
      ? tipo!.toUpperCase() == "PROCESO"
      : tecnologiasProceso.contains(tecnologia);

  bool get resuelto => (estadoFin ?? "").toUpperCase() == "OK";

  factory BitacoraError.fromJson(Map<String, dynamic> json) {
    return BitacoraError(
      id: json["id"],
      fechaHora: DateTime.parse(json["fecha_hora"]),
      fechaActualizacion: json["fecha_actualizacion"] == null
          ? null
          : DateTime.parse(json["fecha_actualizacion"]),
      nombre: json["nombre"],
      tecnologia: json["tecnologia"],
      estado: json["estado"],
      estadoFin: json["estado_fin"],
      tipo: json["tipo"],
      descripcion: json["descripcion"],
    );
  }
}

class BitacoraResumenMes {
  final int mes;
  final int total;
  final bool tieneError;

  BitacoraResumenMes(
      {required this.mes, required this.total, required this.tieneError});

  factory BitacoraResumenMes.fromJson(Map<String, dynamic> json) {
    return BitacoraResumenMes(
        mes: json["mes"],
        total: json["total"],
        tieneError: json["tiene_error"]);
  }
}

class BitacoraResumenAnio {
  final int anio;
  final int totalAnual;
  final double? variacionPct;
  final List<BitacoraResumenMes> meses;

  BitacoraResumenAnio({
    required this.anio,
    required this.totalAnual,
    required this.meses,
    this.variacionPct,
  });

  factory BitacoraResumenAnio.fromJson(Map<String, dynamic> json) {
    return BitacoraResumenAnio(
      anio: json["anio"],
      totalAnual: json["total_anual"],
      variacionPct: (json["variacion_pct"] as num?)?.toDouble(),
      meses: (json["meses"] as List)
          .map((j) => BitacoraResumenMes.fromJson(j))
          .toList(),
    );
  }
}
