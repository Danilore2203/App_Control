class Usuario {
  final int id;
  final String username;
  final String? nombre;
  final String? email;
  final bool activo;
  final bool esAdmin;

  Usuario({
    required this.id,
    required this.username,
    required this.activo,
    required this.esAdmin,
    this.nombre,
    this.email,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json["id"],
      username: json["username"],
      nombre: json["nombre"],
      email: json["email"],
      activo: json["activo"],
      esAdmin: json["es_admin"] ?? false,
    );
  }
}
