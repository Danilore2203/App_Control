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

  Future<Map<String, String>> _headers() async {
    final token = await _authService.obtenerToken();
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token"
    };
  }

  Future<List<Control>> obtenerControles() async {
    final response = await http.get(
      Uri.parse("${AppConfig.apiBaseUrl}/controles"),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception("No se pudieron obtener los controles");
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Control.fromJson(json)).toList();
  }

  Future<List<HistorialFalla>> obtenerHistorialFallas({int dias = 7}) async {
    final response = await http.get(
      Uri.parse(
          "${AppConfig.apiBaseUrl}/controles/historial-fallas?dias=$dias"),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception("No se pudo obtener el historial de fallas");
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => HistorialFalla.fromJson(json)).toList();
  }

  Future<List<Alerta>> obtenerAlertas() async {
    final response = await http.get(
      Uri.parse("${AppConfig.apiBaseUrl}/alertas"),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception("No se pudieron obtener las alertas");
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Alerta.fromJson(json)).toList();
  }

  Future<void> registrarFcmToken(String fcmToken) async {
    await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/auth/me/fcm-token"),
      headers: await _headers(),
      body: jsonEncode({"fcm_token": fcmToken}),
    );
  }

  Future<Usuario> obtenerPerfil() async {
    final response = await http.get(
      Uri.parse("${AppConfig.apiBaseUrl}/auth/me"),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception("No se pudo obtener el perfil");
    }

    return Usuario.fromJson(jsonDecode(response.body));
  }

  Future<List<SolicitudAcceso>> obtenerSolicitudes(
      {String estado = "pendiente"}) async {
    final response = await http.get(
      Uri.parse("${AppConfig.apiBaseUrl}/admin/solicitudes?estado=$estado"),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception("No se pudieron obtener las solicitudes");
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => SolicitudAcceso.fromJson(json)).toList();
  }

  Future<void> aprobarSolicitud(int id) async {
    final response = await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/admin/solicitudes/$id/aprobar"),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception("No se pudo aprobar la solicitud");
    }
  }

  Future<void> rechazarSolicitud(int id) async {
    final response = await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/admin/solicitudes/$id/rechazar"),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception("No se pudo rechazar la solicitud");
    }
  }

  Future<BitacoraResumenAnio> obtenerBitacoraResumen(int anio) async {
    final response = await http.get(
      Uri.parse("${AppConfig.apiBaseUrl}/bitacora/resumen?anio=$anio"),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception("No se pudo obtener el resumen de la bitácora");
    }
    return BitacoraResumenAnio.fromJson(jsonDecode(response.body));
  }

  Future<List<BitacoraError>> obtenerBitacoraEntradas(int anio,
      {int? mes}) async {
    final query = mes == null ? "anio=$anio" : "anio=$anio&mes=$mes";
    final response = await http.get(
      Uri.parse("${AppConfig.apiBaseUrl}/bitacora?$query"),
      headers: await _headers(),
    );
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
    final response = await http.post(
      Uri.parse("${AppConfig.apiBaseUrl}/bitacora"),
      headers: await _headers(),
      body: jsonEncode({
        "nombre": nombre,
        "tecnologia": tecnologia,
        "estado": estado,
        "descripcion": descripcion,
        if (fechaHora != null) "fecha_hora": fechaHora.toIso8601String(),
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
          _extraerDetalleError(response, "No se pudo registrar la entrada."));
    }
  }

  String _extraerDetalleError(
      http.Response response, String mensajePorDefecto) {
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
