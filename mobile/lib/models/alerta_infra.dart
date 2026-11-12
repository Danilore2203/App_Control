import "../utils/formato.dart";

/// Alarma de infraestructura que no es de un proceso (hoy: congestión en
/// Netezza). La detecta OP_PROD; el backend la guarda en UTC sin zona.
class AlertaInfra {
  final String clave;
  final bool abierta;
  final String titulo;
  final String mensaje;
  final DateTime? abiertaEn;

  const AlertaInfra({required this.clave, required this.abierta, required this.titulo, required this.mensaje, this.abiertaEn});

  factory AlertaInfra.fromJson(Map<String, dynamic> j) => AlertaInfra(
        clave: (j["clave"] ?? "").toString(),
        abierta: j["abierta"] == true,
        titulo: (j["titulo"] ?? j["clave"] ?? "").toString(),
        mensaje: (j["mensaje"] ?? "").toString(),
        abiertaEn: j["abierta_en"] == null ? null : fechaUtc(j["abierta_en"].toString()),
      );
}

/// Un paso del historial: se abrió, sigue (recordatorio) o se cerró.
class EventoInfra {
  final String tipo; // abre | sigue | cierra
  final String titulo;
  final String mensaje;
  final DateTime creadoEn;

  const EventoInfra({required this.tipo, required this.titulo, required this.mensaje, required this.creadoEn});

  factory EventoInfra.fromJson(Map<String, dynamic> j) => EventoInfra(
        tipo: (j["tipo"] ?? "").toString(),
        titulo: (j["titulo"] ?? "").toString(),
        mensaje: (j["mensaje"] ?? "").toString(),
        creadoEn: fechaUtc(j["creado_en"].toString()),
      );
}

class AlertasInfra {
  final List<AlertaInfra> activas;
  final List<EventoInfra> eventos;

  const AlertasInfra({this.activas = const [], this.eventos = const []});

  factory AlertasInfra.fromJson(Map<String, dynamic> j) => AlertasInfra(
        activas: ((j["activas"] as List?) ?? const [])
            .whereType<Map>()
            .map((a) => AlertaInfra.fromJson(Map<String, dynamic>.from(a)))
            .toList(),
        eventos: ((j["eventos"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => EventoInfra.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
