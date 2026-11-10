import "../utils/formato.dart";

/// Un reporte del Monitor FTP de la web (los Excel que se abren en el
/// servidor 208 y depositan su archivo en el FTP), como lo devuelve OP_PROD
/// con el comando `reportes.resumen`.
class ReporteFtp {
  final String archivo;
  final String estado; // OK | NO DEPOSITADO | DEMORADO | EN PROCESO | ALMACENADO
  final String color; // green | red | orange | gray | blue
  final String tipo; // ROBBY_REPORT, 24X7, OP, BI...
  final String? horaProgramada; // «Programada» en la web
  final String? horaDeposito; // «Depósito» (solo si fue hoy)
  final String? fechaModificacion;
  final num? tamanioMb;
  final num? descargas3m;
  final String? ruta;

  const ReporteFtp({
    required this.archivo,
    required this.estado,
    required this.color,
    required this.tipo,
    this.horaProgramada,
    this.horaDeposito,
    this.fechaModificacion,
    this.tamanioMb,
    this.descargas3m,
    this.ruta,
  });

  factory ReporteFtp.fromJson(Map<String, dynamic> json) => ReporteFtp(
        archivo: (json["archivo"] ?? "").toString(),
        estado: (json["estado"] ?? "").toString(),
        color: (json["color"] ?? "gray").toString(),
        tipo: (json["tipo"] ?? "").toString(),
        horaProgramada: _texto(json["hora_programada"]),
        horaDeposito: _texto(json["hora_deposito"]),
        fechaModificacion: _texto(json["fecha_modificacion"]),
        tamanioMb: leerNumero(json["tamanio_mb"]),
        descargas3m: leerNumero(json["descargas_3m"]),
        ruta: _texto(json["ruta"]),
      );
}

String? _texto(Object? v) {
  final s = v?.toString().trim() ?? "";
  return s.isEmpty ? null : s;
}

/// Un libro en la cola de aperturas del 208.
class ItemColaReportes {
  final String id;
  final String archivo;
  final String estado; // pendiente | abriendo | abierto | colgado | terminado | error | cancelado
  final String origen; // cola | manual
  final String usuario;
  final String? horaProgramada;
  final String mensaje;

  const ItemColaReportes({
    required this.id,
    required this.archivo,
    required this.estado,
    required this.origen,
    required this.usuario,
    this.horaProgramada,
    this.mensaje = "",
  });

  factory ItemColaReportes.fromJson(Map<String, dynamic> json) => ItemColaReportes(
        id: (json["id"] ?? "").toString(),
        archivo: (json["archivo"] ?? "").toString(),
        estado: (json["estado"] ?? "").toString(),
        origen: (json["origen"] ?? "").toString(),
        usuario: (json["usuario"] ?? "").toString(),
        horaProgramada: _texto(json["hora_programada"]),
        mensaje: (json["mensaje"] ?? "").toString(),
      );

  bool get vivo => const {"pendiente", "abriendo", "abierto", "colgado"}.contains(estado);
}

/// La «Cola de aperturas» del Monitor FTP: abre los reportes de a pocos para
/// no saturar el 208, cada uno a su hora programada.
class ColaReportes {
  final String estado; // inactiva | corriendo | pausada | deteniendo | terminada
  final String mensaje;
  final String? iniciadaPor;
  final String? proximaHora;
  final bool auto;
  final int maxAbiertos;
  final List<String> tipos;
  final Map<String, int> conteo;
  final List<ItemColaReportes> items;

  const ColaReportes({
    required this.estado,
    this.mensaje = "",
    this.iniciadaPor,
    this.proximaHora,
    this.auto = false,
    this.maxAbiertos = 2,
    this.tipos = const [],
    this.conteo = const {},
    this.items = const [],
  });

  static const vacia = ColaReportes(estado: "inactiva");

  factory ColaReportes.fromJson(Map<String, dynamic>? json) {
    if (json == null) return vacia;
    return ColaReportes(
      estado: (json["estado"] ?? "inactiva").toString(),
      mensaje: (json["mensaje"] ?? "").toString(),
      iniciadaPor: _texto(json["iniciada_por"]),
      proximaHora: _texto(json["proxima_hora"]),
      auto: json["auto"] == true,
      maxAbiertos: leerNumero(json["max_abiertos"])?.toInt() ?? 2,
      tipos: ((json["tipos"] as List?) ?? const []).map((t) => t.toString()).toList(),
      conteo: {
        for (final e in ((json["conteo"] as Map?) ?? const {}).entries)
          e.key.toString(): leerNumero(e.value)?.toInt() ?? 0,
      },
      items: ((json["items"] as List?) ?? const [])
          .whereType<Map>()
          .map((i) => ItemColaReportes.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
    );
  }

  int get abiertos => (conteo["abiertos"] ?? 0);
  int get pendientes => conteo["pendientes"] ?? 0;
  int get terminados => conteo["terminados"] ?? 0;
  int get errores => conteo["errores"] ?? 0;
  int get colgados => conteo["colgados"] ?? 0;

  /// Corriendo, pausada o terminando de cerrar: no se puede iniciar otra.
  bool get enMarcha => const {"corriendo", "pausada", "deteniendo"}.contains(estado);

  /// Puede cancelar sus pendientes (como «Cancelar pendientes» en la web).
  bool get sePuedeDetener => estado == "corriendo" || estado == "pausada";

  bool get finalizada => estado == "terminada" || estado == "inactiva";

  List<ItemColaReportes> get vivos => items.where((i) => i.vivo).toList();
}

/// Monitor de reportes completo: filas, contadores por color y la cola.
class ReportesMonitor {
  final List<ReporteFtp> filas;
  final Map<String, int> resumen; // green, red, orange, gray, blue, todos (sin almacenados)
  final ColaReportes cola;

  const ReportesMonitor({required this.filas, required this.resumen, required this.cola});

  static const vacio = ReportesMonitor(filas: [], resumen: {}, cola: ColaReportes.vacia);

  factory ReportesMonitor.fromJson(Map<String, dynamic> json) => ReportesMonitor(
        filas: ((json["filas"] as List?) ?? const [])
            .whereType<Map>()
            .map((f) => ReporteFtp.fromJson(Map<String, dynamic>.from(f)))
            .toList(),
        resumen: {
          for (final e in ((json["resumen"] as Map?) ?? const {}).entries)
            e.key.toString(): leerNumero(e.value)?.toInt() ?? 0,
        },
        cola: ColaReportes.fromJson((json["cola"] as Map?)?.cast<String, dynamic>()),
      );

  int cuenta(String color) => resumen[color] ?? 0;

  /// «Todos» como la web: sin los almacenados.
  int get todos => resumen["todos"] ?? filas.where((f) => f.color != "blue").length;
}

/// Candidato (o descartado) de «Iniciar cola».
class CandidatoCola {
  final String archivo;
  final String tipo;
  final String? horaProgramada;
  final bool yaToca;
  final String? motivo;

  const CandidatoCola({required this.archivo, required this.tipo, this.horaProgramada, this.yaToca = true, this.motivo});

  factory CandidatoCola.fromJson(Map<String, dynamic> json) => CandidatoCola(
        archivo: (json["archivo"] ?? "").toString(),
        tipo: (json["tipo"] ?? "").toString(),
        horaProgramada: _texto(json["hora_programada"]),
        yaToca: json["ya_toca"] != false,
        motivo: _texto(json["motivo"]),
      );
}

class CandidatosCola {
  final List<CandidatoCola> elegibles;
  final List<CandidatoCola> omitidos;

  const CandidatosCola({required this.elegibles, required this.omitidos});

  factory CandidatosCola.fromJson(Map<String, dynamic> json) {
    List<CandidatoCola> lista(Object? v) => ((v as List?) ?? const [])
        .whereType<Map>()
        .map((c) => CandidatoCola.fromJson(Map<String, dynamic>.from(c)))
        .toList();
    return CandidatosCola(elegibles: lista(json["elegibles"]), omitidos: lista(json["omitidos"]));
  }

  int get yaTocan => elegibles.where((c) => c.yaToca).length;
}
