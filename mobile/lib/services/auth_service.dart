import "dart:convert";

import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:google_sign_in/google_sign_in.dart";
import "package:http/http.dart" as http;

import "../config.dart";

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = "access_token";
  static const _infraTokenKey = "infra_token";

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

  Future<void> login(String username, String password) async {
    final response = await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/auth/login"),
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: {"username": username, "password": password},
    );

    if (response.statusCode != 200) {
      throw Exception(_extraerDetalle(response, "Usuario o contraseña incorrectos."));
    }

    final data = jsonDecode(response.body);
    await _storage.write(key: _tokenKey, value: data["access_token"]);
    await _guardarInfraToken(data);
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
    final response = await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/auth/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password, "nombre": nombre, "email": email}),
    );

    if (response.statusCode != 200) {
      throw Exception(_extraerDetalle(response, "No se pudo crear la cuenta."));
    }
  }

  Future<void> configurarPassword({
    required String username,
    required String passwordActual,
    required String passwordNueva,
  }) async {
    final response = await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/auth/configurar-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "username": username,
        "password_actual": passwordActual,
        "password_nueva": passwordNueva,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(_extraerDetalle(response, "No se pudo configurar la contraseña."));
    }

    final data = jsonDecode(response.body);
    await _storage.write(key: _tokenKey, value: data["access_token"]);
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

    final response = await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/auth/login/google"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"id_token": idToken}),
    );

    if (response.statusCode != 200) {
      await _googleSignIn.signOut();
      throw Exception(_extraerDetalle(response, "Esa cuenta de Google no está autorizada."));
    }

    final data = jsonDecode(response.body);
    await _storage.write(key: _tokenKey, value: data["access_token"]);
  }

  Future<String?> obtenerToken() => _storage.read(key: _tokenKey);

  /// Token del monitor OP (Netezza/PostgreSQL DEV/PROD). Nulo si el usuario
  /// entro por Google o si el monitor no estaba disponible al hacer login.
  Future<String?> obtenerInfraToken() => _storage.read(key: _infraTokenKey);

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _infraTokenKey);
    await _googleSignIn.signOut();
  }

  Future<bool> estaAutenticado() async {
    final token = await obtenerToken();
    return token != null;
  }
}
