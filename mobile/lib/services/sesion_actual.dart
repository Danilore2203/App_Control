import "../models/usuario.dart";

/// Perfil del usuario logueado, para que cualquier pantalla sepa si puede
/// ejecutar acciones (lanzar procesos, cancelar sesiones...) sin volver a
/// pedir /auth/me. Lo carga el dashboard al entrar; vacio = sin permisos.
class SesionActual {
  static Usuario? usuario;

  static bool get esAdmin => usuario?.esAdmin ?? false;
}
