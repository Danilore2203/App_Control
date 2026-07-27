class HistorialFalla {
  final DateTime fecha;
  final int fallas;

  HistorialFalla({required this.fecha, required this.fallas});

  factory HistorialFalla.fromJson(Map<String, dynamic> json) {
    return HistorialFalla(
      fecha: DateTime.parse(json["fecha"]),
      fallas: json["fallas"],
    );
  }
}
