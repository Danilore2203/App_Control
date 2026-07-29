import "package:http/http.dart" as http;

import "auth_service.dart";
import "navegacion_service.dart";

/// Envuelve una peticion HTTP para que, si el backend responde 401 (token
/// vencido), intente refrescar la sesion sola y reintente UNA vez, en vez
/// de que el usuario vea un error generico como si fuera un problema de
/// red. Si el refresh_token tambien esta vencido/invalido, recien ahi
/// limpia la sesion y manda al usuario al login.
class ApiClient {
  static final _authService = AuthService();

  static Future<http.Response> enviar(Future<http.Response> Function() peticion) async {
    final respuesta = await peticion();
    if (respuesta.statusCode != 401) return respuesta;

    try {
      await _authService.refrescarToken();
    } on SesionExpiradaException {
      await _authService.logout();
      NavegacionService.irALogin();
      rethrow;
    }

    // _headers() de quien llama vuelve a leer el token del storage, que ya
    // quedo actualizado por refrescarToken() - no hace falta pasarlo a mano.
    return peticion();
  }
}
