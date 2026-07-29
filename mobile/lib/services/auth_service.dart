import "dart:async";
import "dart:convert";

import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:google_sign_in/google_sign_in.dart";
import "package:http/http.dart" as http;

import "../config.dart";
import "../models/usuario.dart";

/// Se lanza cuando el refresh_token tambien esta vencido/invalido: ahi si
/// hay que loguearse de nuevo a mano, no antes.
class SesionExpiradaException implements Exception {}

/// Se lanza cuando el login falla porque la cuenta (tipicamente AD) todavia
/// no tiene una contrasena local configurada para la app.
class RequiereConfigurarPasswordException implements Exception {
  final String mensaje;

  RequiereConfigurarPasswordException(this.mensaje);

  @override
  String toString() => mensaje;
}

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = "access_token";
  static const _refreshTokenKey = "refresh_token";
  static const _infraTokenKey = "infra_token";
  // Mas largo que en ApiService: el login ademas espera a que el backend
  // consulte el monitor de AD, que puede tardar unos segundos.
  static const _timeout = Duration(seconds: 20);
  static const _timeoutMsg = "El servidor no respondió a tiempo. Probá de nuevo.";

  final _googleSignIn = kIsWeb
      ? GoogleSignIn(clientId: AppConfig.googleServerClientId, scopes: ["email"])
      : GoogleSignIn(serverClientId: AppConfig.googleServerClientId, scopes: ["email"]);

  String _extraerDetalle(http.Response response, String mensajePorDefecto) {
    try {
      final cuerpo = jsonDecode(response.body);
      if (cuerpo is Map && cuerpo["detail"] is String) {
        return cuerpo["detail"] as String;
      }
    } catch (_) {
      // Si el cuerpo no es JSON valido, se usa el mensaje generico.
    }
    return mensajePorDefecto;
  }

  Map<String, dynamic>? _detalleObjeto(http.Response response) {
    try {
      final cuerpo = jsonDecode(response.body);
      if (cuerpo is Map && cuerpo["detail"] is Map) {
        return Map<String, dynamic>.from(cuerpo["detail"] as Map);
      }
    } catch (_) {
      // Si el cuerpo no es JSON valido, no hay detalle estructurado.
    }
    return null;
  }

  Future<void> login(String username, String password) async {
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/login"),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {"username": username, "password": password},
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      final detalle = _detalleObjeto(response);
      if (detalle?["codigo"] == "sin_password") {
        throw RequiereConfigurarPasswordException(
          detalle!["mensaje"] as String? ?? "Configura tu contraseña para continuar.",
        );
      }
      throw Exception(_extraerDetalle(response, "Usuario o contraseña incorrectos."));
    }

    final data = jsonDecode(response.body);
    await _guardarTokens(data);
    await _guardarInfraToken(data);
  }

  Future<void> _guardarTokens(Map<String, dynamic> data) async {
    await _storage.write(key: _tokenKey, value: data["access_token"]);
    final refreshToken = data["refresh_token"];
    if (refreshToken is String && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  Future<void> _guardarInfraToken(Map<String, dynamic> data) async {
    final infraToken = data["infra_token"];
    if (infraToken is String && infraToken.isNotEmpty) {
      await _storage.write(key: _infraTokenKey, value: infraToken);
    } else {
      await _storage.delete(key: _infraTokenKey);
    }
  }

  Future<void> registrar({
    required String username,
    required String password,
    String? nombre,
    String? email,
  }) async {
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/register"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"username": username, "password": password, "nombre": nombre, "email": email}),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      throw Exception(_extraerDetalle(response, "No se pudo crear la cuenta."));
    }
  }

  Future<void> configurarPassword({
    required String username,
    String? passwordActual,
    String? correoVerificacion,
    required String passwordNueva,
  }) async {
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/configurar-password"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "username": username,
            "password_actual": passwordActual,
            "correo_verificacion": correoVerificacion,
            "password_nueva": passwordNueva,
          }),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      throw Exception(_extraerDetalle(response, "No se pudo configurar la contraseña."));
    }

    final data = jsonDecode(response.body);
    await _guardarTokens(data);
  }

  Future<void> loginConGoogle() async {
    final cuenta = await _googleSignIn.signIn();
    if (cuenta == null) {
      throw Exception("Inicio de sesión con Google cancelado");
    }

    final autenticacion = await cuenta.authentication;
    final idToken = autenticacion.idToken;
    if (idToken == null) {
      throw Exception("No se pudo obtener el token de Google");
    }

    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/login/google"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"id_token": idToken}),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      await _googleSignIn.signOut();
      throw Exception(_extraerDetalle(response, "Esa cuenta de Google no está autorizada."));
    }

    final data = jsonDecode(response.body);
    await _guardarTokens(data);
  }

  /// Asocia una cuenta de Google (puede ser distinta a la del correo de AD)
  /// al usuario ya autenticado en esta sesion. No requiere aprobacion de
  /// admin: el usuario ya probo ser dueno de esta cuenta al iniciar sesion.
  Future<Usuario> vincularGoogle() async {
    final cuenta = await _googleSignIn.signIn();
    if (cuenta == null) {
      throw Exception("Vinculación con Google cancelada");
    }

    final autenticacion = await cuenta.authentication;
    final idToken = autenticacion.idToken;
    if (idToken == null) {
      throw Exception("No se pudo obtener el token de Google");
    }

    final token = await obtenerToken();
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/vincular-google"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          },
          body: jsonEncode({"id_token": idToken}),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      throw Exception(_extraerDetalle(response, "No se pudo vincular la cuenta de Google."));
    }

    return Usuario.fromJson(jsonDecode(response.body));
  }

  Future<Usuario> desvincularGoogle() async {
    final token = await obtenerToken();
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/desvincular-google"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          },
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      throw Exception(_extraerDetalle(response, "No se pudo desvincular la cuenta de Google."));
    }

    return Usuario.fromJson(jsonDecode(response.body));
  }

  Future<String?> obtenerToken() => _storage.read(key: _tokenKey);

  Future<String?> obtenerRefreshToken() => _storage.read(key: _refreshTokenKey);

  /// Token del monitor OP (Netezza/PostgreSQL DEV/PROD). Nulo si el usuario
  /// entro por Google o si el monitor no estaba disponible al hacer login.
  Future<String?> obtenerInfraToken() => _storage.read(key: _infraTokenKey);

  /// Cambia el refresh_token guardado por un access_token nuevo, sin pedir
  /// credenciales de vuelta. Lanza [SesionExpiradaException] especificamente
  /// cuando el refresh_token esta vencido/invalido (ahi si hay que loguearse
  /// de nuevo a mano) - cualquier otro error (red, timeout) se propaga tal
  /// cual, porque no significa que la sesion este realmente muerta.
  Future<void> refrescarToken() async {
    final refreshToken = await obtenerRefreshToken();
    if (refreshToken == null) {
      throw SesionExpiradaException();
    }

    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/refresh"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"refresh_token": refreshToken}),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode == 401) {
      throw SesionExpiradaException();
    }
    if (response.statusCode != 200) {
      throw Exception("No se pudo renovar la sesión.");
    }

    await _guardarTokens(jsonDecode(response.body));
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _infraTokenKey);
    await _googleSignIn.signOut();
  }

  Future<bool> estaAutenticado() async {
    final token = await obtenerToken();
    return token != null;
  }
}
