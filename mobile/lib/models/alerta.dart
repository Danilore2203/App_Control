class Alerta {
  final int id;
  final int controlId;
  final String mensaje;
  final String nivel;
  final bool enviada;
  final DateTime creadoEn;

  Alerta({
    required this.id,
    required this.controlId,
    required this.mensaje,
    required this.nivel,
    required this.enviada,
    required this.creadoEn,
  });

  factory Alerta.fromJson(Map<String, dynamic> json) {
    return Alerta(
      id: json["id"],
      controlId: json["control_id"],
      mensaje: json["mensaje"],
      nivel: json["nivel"],
      enviada: json["enviada"],
      creadoEn: DateTime.parse(json["creado_en"]),
    );
  }
}
