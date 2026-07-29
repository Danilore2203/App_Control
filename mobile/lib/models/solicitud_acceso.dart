/// Una solicitud de acceso pendiente de aprobar. Puede venir de dos origenes
/// distintos en el backend (tablas separadas, por eso `tipo` no viaja en el
/// JSON): "google" (inicio de sesion con una cuenta de Google desconocida) o
/// "registro" (alguien eligio usuario/contraseña a mano en "Crear cuenta").
class SolicitudAcceso {
  final int id;
  final String tipo;
  final String? email;
  final String? username;
  final String? nombre;
  final String estado;
  final DateTime creadoEn;

  SolicitudAcceso({
    required this.id,
    required this.tipo,
    required this.estado,
    required this.creadoEn,
    this.email,
    this.username,
    this.nombre,
  });

  String get identificador => nombre ?? email ?? username ?? "Usuario";

  factory SolicitudAcceso.fromJson(Map<String, dynamic> json, {required String tipo}) {
    return SolicitudAcceso(
      id: json["id"],
      tipo: tipo,
      email: json["email"],
      username: json["username"],
      nombre: json["nombre"],
      estado: json["estado"],
      creadoEn: DateTime.parse(json["creado_en"]),
    );
  }
}
