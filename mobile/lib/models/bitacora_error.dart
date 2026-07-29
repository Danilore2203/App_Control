const tecnologiasProceso = ["AIRFLOW", "DATASTAGE", "PENTAHO"];
const tecnologiasTabla = ["QA_CONTROL", "PG_PROD"];

/// Categorias que el poller genera solo (ERROR, DEMORADO) mas las que quedan
/// disponibles para carga manual - el poller no las genera automaticamente
/// salvo el fallback ADVERTENCIA para estados/colores de origen no mapeados.
const _categoriasManuales = [
  "RESUELTO",
  "ADVERTENCIA",
  "INFORMACION",
  "REINTENTO",
  "EJECUTADO",
];
const estadosProceso = ["ERROR", "DEMORADO", ..._categoriasManuales];
const estadosTabla = [
  "VACIA",
  "ERROR",
  "DATOS_INCORRECTOS",
  ..._categoriasManuales,
];

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
  final int? duracionSegundos;
  final String? sistema;
  final String? origen;

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
    this.duracionSegundos,
    this.sistema,
    this.origen,
  });

  bool get esProceso => tipo != null
      ? tipo!.toUpperCase() == "PROCESO"
      : tecnologiasProceso.contains(tecnologia);

  bool get resuelto => (estadoFin ?? "").toUpperCase() == "OK";

  /// Agrupa el estado crudo en una de las categorias visibles para filtrar
  /// (Errores/Resueltos/Demorados/Ejecutados/Información) - una vez cerrado
  /// el episodio, lo que importa para el usuario es que ya se resolvió, sin
  /// importar si originalmente fue un ERROR, una ADVERTENCIA, etc.
  String get categoria {
    if (resuelto) return "RESUELTO";
    switch ((estado ?? "").toUpperCase()) {
      case "DEMORADO":
        return "DEMORADO";
      case "EJECUTADO":
        return "EJECUTADO";
      case "INFORMACION":
        return "INFORMACION";
      default:
        return "ERROR";
    }
  }

  /// Duración transcurrida hasta ahora si sigue abierto, o la final si ya se
  /// cerró - siempre hay algo que mostrar en la tarjeta.
  Duration get duracionTranscurrida => fechaActualizacion != null
      ? fechaActualizacion!.difference(fechaHora)
      : DateTime.now().difference(fechaHora);

  String get duracionFormateada {
    final segundos =
        duracionSegundos ?? duracionTranscurrida.inSeconds.clamp(0, 1 << 31);
    final horas = segundos ~/ 3600;
    final minutos = (segundos % 3600) ~/ 60;
    return horas > 0 ? "${horas}h ${minutos}m" : "${minutos}m";
  }

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
      duracionSegundos: json["duracion_segundos"],
      sistema: json["sistema"],
      origen: json["origen"],
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
