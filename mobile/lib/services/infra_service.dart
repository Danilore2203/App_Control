import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;

import "../config.dart";
import "../models/netezza_sesion.dart";
import "../models/postgres_sesion.dart";
import "api_client.dart";
import "auth_service.dart";

/// Habla con el monitor OP existente (Netezza / PostgreSQL DEV / PostgreSQL
/// PROD) a traves de nuestro propio backend (/infra/*), que reenvia la
/// llamada server-to-server. Directo desde el navegador choca con CORS
/// (el monitor no espera pedidos cross-origin); nuestro backend no tiene
/// ese problema porque la llamada sale del servidor, no del navegador.
class InfraService {
  final _authService = AuthService();

  static const _timeout = Duration(seconds: 15);
  static const _timeoutMsg = "El monitor de infraestructura no respondió a tiempo. Probá de nuevo.";

  /// El monitor OP a veces devuelve HTML (502/504) en vez de JSON cuando
  /// "despierta" de estar dormido - sin esto, jsonDecode explota con un
  /// FormatException poco claro para el usuario.
  Map<String, dynamic> _decodificar(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception("El monitor de infraestructura no está disponible ahora mismo.");
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await _authService.obtenerToken();
    final infraToken = await _authService.obtenerInfraToken();
    if (infraToken == null) {
      throw Exception(
          "No hay sesión con el monitor de infraestructura. Vuelve a iniciar sesión con usuario y contraseña.");
    }
    return {
      "Authorization": "Bearer $token",
      "X-Infra-Token": infraToken,
      "Accept": "application/json",
      "Content-Type": "application/json",
    };
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await ApiClient.enviar(() async => http
        .get(
          Uri.parse("${AppConfig.apiBaseUrl}/infra$path"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg)));
    final body = _decodificar(response);
    if (response.statusCode != 200 || body["ok"] != true) {
      throw Exception(body["error"]?.toString() ??
          body["detail"]?.toString() ??
          "Error consultando $path");
    }
    return body;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> data) async {
    final response = await ApiClient.enviar(() async => http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/infra$path"),
          headers: await _headers(),
          body: jsonEncode(data),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg)));
    final body = _decodificar(response);
    if (body["ok"] != true) {
      throw Exception(body["error"]?.toString() ??
          body["detail"]?.toString() ??
          "No se pudo completar la acción");
    }
    return body;
  }

  // ---- Netezza ----

  Future<({List<NetezzaSesion> activas, List<NetezzaSesion> idle})>
      obtenerNetezzaSesiones() async {
    final body = await _get("/netezza/sesiones/data");
    final activas =
        (body["active"] as List).map((j) => NetezzaSesion.fromJson(j)).toList();
    final idle =
        (body["idle"] as List).map((j) => NetezzaSesion.fromJson(j)).toList();
    return (activas: activas, idle: idle);
  }

  Future<void> abortarTransaccionNetezza(int sessionId) =>
      _post("/netezza/sesiones/abort-txn", {"session_id": sessionId});

  Future<({int activas, int idle, int total})> netezzaAlertPoll() async {
    final body = await _get("/netezza/sesiones/alert-poll");
    return (
      activas: body["n_active"] as int,
      idle: body["n_idle"] as int,
      total: body["n_total"] as int
    );
  }

  // ---- PostgreSQL (compartido DEV/PROD: mismo formato de datos) ----

  Future<({List<PostgresSesion> filas, int total, int activas})> _postgresData(
      String prefijo, bool soloActivas) async {
    final body =
        await _get("/$prefijo/data?active_only=${soloActivas ? 1 : 0}");
    final filas =
        (body["rows"] as List).map((j) => PostgresSesion.fromJson(j)).toList();
    final counts = body["counts"] as Map<String, dynamic>;
    return (
      filas: filas,
      total: counts["total"] as int,
      activas: counts["active"] as int
    );
  }

  Future<({List<PostgresSesion> filas, int total, int activas})>
      obtenerPostgresDev({bool soloActivas = true}) =>
          _postgresData("monpost", soloActivas);

  Future<({List<PostgresSesion> filas, int total, int activas})>
      obtenerPostgresProd({bool soloActivas = true}) =>
          _postgresData("postprod", soloActivas);

  Future<void> cancelarSesionPostgresDev(int pid) =>
      _post("/monpost/cancel", {"pid": pid});

  Future<void> cancelarSesionPostgresProd(int pid) =>
      _post("/postprod/cancel", {"pid": pid});

  Future<({int total, int activas, int bloqueadas})> _postgresAlertPoll(
      String prefijo) async {
    final body = await _get("/$prefijo/alert-poll");
    return (
      total: body["n_total"] as int,
      activas: body["n_active"] as int,
      bloqueadas: body["n_blocked"] as int,
    );
  }

  Future<({int total, int activas, int bloqueadas})> postgresDevAlertPoll() =>
      _postgresAlertPoll("monpost");

  Future<({int total, int activas, int bloqueadas})> postgresProdAlertPoll() =>
      _postgresAlertPoll("postprod");

  Future<int> tamanoBaseDatos(String prefijo) async {
    final body = await _get("/$prefijo/disk-poll");
    return (body["db_size_bytes"] as num).toInt();
  }
}
