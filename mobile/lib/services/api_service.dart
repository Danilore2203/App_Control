import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;

import "../config.dart";
import "../models/alerta.dart";
import "../models/bitacora_error.dart";
import "../models/control.dart";
import "../models/historial_falla.dart";
import "../models/solicitud_acceso.dart";
import "../models/usuario.dart";
import "auth_service.dart";

class ApiService {
  final AuthService _authService = AuthService();

  static const _timeout = Duration(seconds: 15);
  static const _timeoutMsg = "El servidor no respondió a tiempo. Probá de nuevo.";

  Future<Map<String, String>> _headers() async {
    final token = await _authService.obtenerToken();
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token"
    };
  }

  Future<List<Control>> obtenerControles() async {
    final response = await http
        .get(
          Uri.parse("${AppConfig.apiBaseUrl}/controles"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      throw Exception("No se pudieron obtener los controles");
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Control.fromJson(json)).toList();
  }

  Future<List<HistorialFalla>> obtenerHistorialFallas({int dias = 7}) async {
    final response = await http
        .get(
          Uri.parse("${AppConfig.apiBaseUrl}/controles/historial-fallas?dias=$dias"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      throw Exception("No se pudo obtener el historial de fallas");
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => HistorialFalla.fromJson(json)).toList();
  }

  Future<List<Alerta>> obtenerAlertas() async {
    final response = await http
        .get(
          Uri.parse("${AppConfig.apiBaseUrl}/alertas"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      throw Exception("No se pudieron obtener las alertas");
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Alerta.fromJson(json)).toList();
  }

  Future<void> registrarFcmToken(String fcmToken) async {
    await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/me/fcm-token"),
          headers: await _headers(),
          body: jsonEncode({"fcm_token": fcmToken}),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));
  }

  Future<void> eliminarFcmToken() async {
    await http
        .delete(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/me/fcm-token"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));
  }

  Future<void> probarAlerta() async {
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/me/probar-alerta"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));
    if (response.statusCode != 200) {
      throw Exception(_extraerDetalleError(response, "No se pudo mandar la alerta de prueba."));
    }
  }

  Future<Usuario> obtenerPerfil() async {
    final response = await http
        .get(
          Uri.parse("${AppConfig.apiBaseUrl}/auth/me"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));

    if (response.statusCode != 200) {
      throw Exception("No se pudo obtener el perfil");
    }

    return Usuario.fromJson(jsonDecode(response.body));
  }

  /// Trae solicitudes de acceso pendientes de AMBOS origenes (Google y
  /// registro local con usuario/contraseña) y las combina en una sola lista,
  /// ordenada por fecha. Los endpoints son distintos porque son tablas
  /// distintas en el backend (una cuenta de Google no tiene contraseña).
  Future<List<SolicitudAcceso>> obtenerSolicitudes({String estado = "pendiente"}) async {
    final headers = await _headers();
    final respuestas = await Future.wait([
      http
          .get(Uri.parse("${AppConfig.apiBaseUrl}/admin/solicitudes?estado=$estado"), headers: headers)
          .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg)),
      http
          .get(Uri.parse("${AppConfig.apiBaseUrl}/admin/solicitudes-registro?estado=$estado"),
              headers: headers)
          .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg)),
    ]);

    if (respuestas[0].statusCode != 200 || respuestas[1].statusCode != 200) {
      throw Exception("No se pudieron obtener las solicitudes");
    }

    final google = (jsonDecode(respuestas[0].body) as List)
        .map((json) => SolicitudAcceso.fromJson(json, tipo: "google"));
    final registro = (jsonDecode(respuestas[1].body) as List)
        .map((json) => SolicitudAcceso.fromJson(json, tipo: "registro"));

    final todas = [...google, ...registro]..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    return todas;
  }

  Future<void> aprobarSolicitud(SolicitudAcceso solicitud) async {
    final ruta = solicitud.tipo == "registro" ? "solicitudes-registro" : "solicitudes";
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/admin/$ruta/${solicitud.id}/aprobar"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));
    if (response.statusCode != 200) {
      throw Exception(_extraerDetalleError(response, "No se pudo aprobar la solicitud"));
    }
  }

  Future<void> rechazarSolicitud(SolicitudAcceso solicitud) async {
    final ruta = solicitud.tipo == "registro" ? "solicitudes-registro" : "solicitudes";
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/admin/$ruta/${solicitud.id}/rechazar"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));
    if (response.statusCode != 200) {
      throw Exception(_extraerDetalleError(response, "No se pudo rechazar la solicitud"));
    }
  }

  Future<BitacoraResumenAnio> obtenerBitacoraResumen(int anio) async {
    final response = await http
        .get(
          Uri.parse("${AppConfig.apiBaseUrl}/bitacora/resumen?anio=$anio"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));
    if (response.statusCode != 200) {
      throw Exception("No se pudo obtener el resumen de la bitácora");
    }
    return BitacoraResumenAnio.fromJson(jsonDecode(response.body));
  }

  Future<List<BitacoraError>> obtenerBitacoraEntradas(int anio, {int? mes}) async {
    final query = mes == null ? "anio=$anio" : "anio=$anio&mes=$mes";
    final response = await http
        .get(
          Uri.parse("${AppConfig.apiBaseUrl}/bitacora?$query"),
          headers: await _headers(),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));
    if (response.statusCode != 200) {
      throw Exception("No se pudieron obtener las entradas de la bitácora");
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => BitacoraError.fromJson(json)).toList();
  }

  Future<void> crearEntradaBitacora({
    required String nombre,
    required String tecnologia,
    required String estado,
    required String descripcion,
    DateTime? fechaHora,
  }) async {
    final response = await http
        .post(
          Uri.parse("${AppConfig.apiBaseUrl}/bitacora"),
          headers: await _headers(),
          body: jsonEncode({
            "nombre": nombre,
            "tecnologia": tecnologia,
            "estado": estado,
            "descripcion": descripcion,
            if (fechaHora != null) "fecha_hora": fechaHora.toIso8601String(),
          }),
        )
        .timeout(_timeout, onTimeout: () => throw TimeoutException(_timeoutMsg));
    if (response.statusCode != 200) {
      throw Exception(_extraerDetalleError(response, "No se pudo registrar la entrada."));
    }
  }

  String _extraerDetalleError(http.Response response, String mensajePorDefecto) {
    try {
      final cuerpo = jsonDecode(response.body);
      if (cuerpo is Map && cuerpo["detail"] != null) {
        final detalle = cuerpo["detail"];
        if (detalle is String) return detalle;
        if (detalle is List && detalle.isNotEmpty && detalle.first is Map) {
          return (detalle.first["msg"] ?? mensajePorDefecto).toString();
        }
      }
    } catch (_) {
      // Cuerpo no es JSON valido: se usa el mensaje generico.
    }
    return mensajePorDefecto;
  }
}
