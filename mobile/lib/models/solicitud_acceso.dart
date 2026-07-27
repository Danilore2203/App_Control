class SolicitudAcceso {
  final int id;
  final String email;
  final String? nombre;
  final String estado;
  final DateTime creadoEn;

  SolicitudAcceso({
    required this.id,
    required this.email,
    required this.estado,
    required this.creadoEn,
    this.nombre,
  });

  factory SolicitudAcceso.fromJson(Map<String, dynamic> json) {
    return SolicitudAcceso(
      id: json["id"],
      email: json["email"],
      nombre: json["nombre"],
      estado: json["estado"],
      creadoEn: DateTime.parse(json["creado_en"]),
    );
  }
}
