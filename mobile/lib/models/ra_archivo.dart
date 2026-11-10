import "../utils/formato.dart";

/// Fila del Monitor RA (ultima carga por archivo en la tabla silver), tal
/// como la devuelve OP_PROD con el comando `ra.resumen`.
class RaArchivo {
  final String archivo;
  final String proceso;
  final String estado; // OK | ERROR | VALIDACION | EN PROCESO
  final String color; // green | red | orange | gray | blue
  final String? fechaHora;
  final num? tamano;
  final num? tamanoRef;

  /// Carpeta del FTP donde se deposita el archivo (DIRECCION_FTP_2).
  final String? ruta;

  const RaArchivo({
    required this.archivo,
    required this.proceso,
    required this.estado,
    required this.color,
    this.fechaHora,
    this.tamano,
    this.tamanoRef,
    this.ruta,
  });

  factory RaArchivo.fromJson(Map<String, dynamic> json) => RaArchivo(
        archivo: (json["archivo"] ?? "").toString(),
        proceso: (json["proceso"] ?? "").toString(),
        estado: (json["estado"] ?? "").toString(),
        color: (json["color"] ?? "gray").toString(),
        fechaHora: json["fecha_hora"]?.toString(),
        // MySQL devuelve TAMAÑO como Decimal y puede llegar como texto ("1234.00").
        tamano: leerNumero(json["tamano"]),
        tamanoRef: leerNumero(json["tamano_ref"]),
        ruta: _textoRa(json["ruta"]),
      );
}

String? _textoRa(Object? v) {
  final s = v?.toString().trim() ?? "";
  return s.isEmpty ? null : s;
}

/// Proceso del que depende un archivo RA (el que lo genera) o que lo usa,
/// como en el detalle del Monitor RA de la web.
class RaDependencia {
  final String proceso;
  final String? tipo; // job_DataStage | job_Pentaho | job_airflow
  final String? fuente; // DATASTAGE | PENTAHO | AIRFLOW (lo que entiende «Ejecutar»)
  final String? ruta; // ruta del job DataStage (PROYECTO/.../Job)
  final String? horaProgramada;
  final String? horaLog; // ultima corrida registrada
  final String estado; // OK | ERROR | DEMORADO | EN TIEMPO | SIN REGISTRO
  final String? responsable;

  const RaDependencia({
    required this.proceso,
    required this.estado,
    this.tipo,
    this.fuente,
    this.ruta,
    this.horaProgramada,
    this.horaLog,
    this.responsable,
  });

  factory RaDependencia.fromJson(Map<String, dynamic> json) => RaDependencia(
        proceso: (json["proceso"] ?? "").toString(),
        estado: (json["estado"] ?? "SIN REGISTRO").toString(),
        tipo: _textoRa(json["tipo"]),
        fuente: _textoRa(json["fuente"]),
        ruta: _textoRa(json["ruta"]),
        horaProgramada: _textoRa(json["hora_programada"]),
        horaLog: _textoRa(json["hora_log"]),
        responsable: _textoRa(json["responsable"]),
      );

  /// Se puede lanzar desde la app (DataStage, Pentaho o Airflow).
  bool get lanzable => fuente != null && proceso.isNotEmpty;

  /// «DataStage», «Pentaho», «Airflow» para mostrar.
  String get fuenteLegible => switch (fuente) {
        "DATASTAGE" => "DataStage",
        "PENTAHO" => "Pentaho",
        "AIRFLOW" => "Airflow",
        _ => tipo ?? "",
      };
}

/// `ra.detalle`: el archivo, de que procesos depende y cuales lo usan.
class RaDetalle {
  final RaArchivo? archivo;
  final List<RaDependencia> dependeDe;
  final List<RaDependencia> loUsan;

  const RaDetalle({this.archivo, this.dependeDe = const [], this.loUsan = const []});

  factory RaDetalle.fromJson(Map<String, dynamic> json) {
    List<RaDependencia> lista(Object? v) => ((v as List?) ?? const [])
        .whereType<Map>()
        .map((d) => RaDependencia.fromJson(Map<String, dynamic>.from(d)))
        .toList();
    final detalle = json["detalle"];
    return RaDetalle(
      archivo: detalle is Map ? RaArchivo.fromJson(Map<String, dynamic>.from(detalle)) : null,
      dependeDe: lista(json["padres"]),
      loUsan: lista(json["hijos"]),
    );
  }
}

/// Resultado de sincronizar una configuracion FTP (una fila de qa_ftp_mysql).
class RaSincronizacion {
  final String nombre;
  final bool ok;
  final int insertados;
  final String mensaje;

  const RaSincronizacion({required this.nombre, required this.ok, required this.insertados, required this.mensaje});

  factory RaSincronizacion.fromJson(Map<String, dynamic> json) => RaSincronizacion(
        nombre: (json["nombre"] ?? "").toString(),
        ok: json["ok"] == true,
        insertados: (json["insertados"] as num?)?.toInt() ?? 0,
        mensaje: (json["mensaje"] ?? "").toString(),
      );
}

/// Monitor RA completo: filas + contadores por color, como la web.
class RaMonitor {
  final List<RaArchivo> filas;
  final Map<String, int> resumen; // green, red, orange, blue, gray, todos

  const RaMonitor({required this.filas, required this.resumen});

  factory RaMonitor.fromJson(Map<String, dynamic> json) => RaMonitor(
        filas: ((json["filas"] as List?) ?? const [])
            .whereType<Map>()
            .map((f) => RaArchivo.fromJson(Map<String, dynamic>.from(f)))
            .toList(),
        resumen: {
          for (final e in ((json["resumen"] as Map?) ?? const {}).entries) e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        },
      );

  int cuenta(String color) => resumen[color] ?? 0;
  int get total => resumen["todos"] ?? filas.length;
  int get enProceso => cuenta("gray") + cuenta("blue");
}

/// Lo que devuelve `ra.actualizar_todos`: como fue la sincronizacion y el
/// monitor ya releido.
class RaActualizacion {
  final String mensaje;
  final int duracionSeg;
  final int insertados;
  final List<RaSincronizacion> resultados;
  final RaMonitor monitor;

  const RaActualizacion({
    required this.mensaje,
    required this.duracionSeg,
    required this.insertados,
    required this.resultados,
    required this.monitor,
  });

  factory RaActualizacion.fromJson(Map<String, dynamic> json) => RaActualizacion(
        mensaje: (json["mensaje"] ?? "").toString(),
        duracionSeg: (json["duracion_seg"] as num?)?.toInt() ?? 0,
        insertados: (json["insertados"] as num?)?.toInt() ?? 0,
        resultados: ((json["resultados"] as List?) ?? const [])
            .whereType<Map>()
            .map((r) => RaSincronizacion.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
        monitor: RaMonitor.fromJson(json),
      );

  int get conError => resultados.where((r) => !r.ok).length;
}
