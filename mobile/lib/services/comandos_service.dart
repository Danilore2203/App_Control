import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;

import "../config.dart";
import "api_client.dart";
import "auth_service.dart";
import "ejecucion_actual.dart";

/// Resultado de un comando ejecutado por OP_PROD adentro de la red.
class ResultadoComando {
  final int id;
  final String estado; // ok | error | expirado
  final Map<String, dynamic> resultado;
  final String? error;

  const ResultadoComando({required this.id, required this.estado, required this.resultado, this.error});

  bool get ok => estado == "ok";
}

class ComandoFallidoException implements Exception {
  final String mensaje;
  ComandoFallidoException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// La app no puede hablar directo con el servidor OP (esta en la red
/// interna de Nuevatel): deja un comando en nuestro backend, OP_PROD lo
/// retira cada pocos segundos, lo ejecuta y deja el resultado; aca se
/// espera consultando hasta que termine. Tarda unos segundos; si OP_PROD
/// esta apagado o sin red, el backend lo da por expirado a los 2 minutos.
class ComandosService {
  final _authService = AuthService();

  static const _timeoutHttp = Duration(seconds: 20);
  static const _intervaloConsulta = Duration(seconds: 2);

  Future<Map<String, String>> _headers() async {
    final token = await _authService.obtenerToken();
    return {"Content-Type": "application/json", "Authorization": "Bearer $token"};
  }

  Map<String, dynamic> _decodificar(http.Response r) {
    try {
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      throw ComandoFallidoException("El servidor no respondió correctamente (${r.statusCode}).");
    }
  }

  /// Crea el comando y espera su resultado (hasta `espera`). Lanza
  /// [ComandoFallidoException] con el mensaje de OP_PROD si fallo o expiro.
  /// Con `titulo`, publica el avance en [EjecucionActual] (la barra flotante
  /// que ve el usuario); sin titulo es una consulta silenciosa.
  Future<ResultadoComando> ejecutar(
    String tipo, {
    Map<String, dynamic> payload = const {},
    Duration espera = const Duration(seconds: 90),
    String? titulo,
    bool anunciarFinal = true,
  }) async {
    void fase(FaseEjecucion f, String detalle) {
      if (titulo == null) return;
      EjecucionActual.mostrar(EstadoEjecucion(titulo: titulo, detalle: detalle, fase: f));
    }

    try {
      fase(FaseEjecucion.enviando, "Enviando la orden…");
      final creado = await ApiClient.enviar(() async => http
          .post(
            Uri.parse("${AppConfig.apiBaseUrl}/comandos"),
            headers: await _headers(),
            body: jsonEncode({"tipo": tipo, "payload": payload}),
          )
          .timeout(_timeoutHttp, onTimeout: () => throw TimeoutException("El servidor no respondió a tiempo.")));
      final cuerpo = _decodificar(creado);
      if (creado.statusCode != 200) {
        throw ComandoFallidoException(cuerpo["detail"]?.toString() ?? "No se pudo enviar la orden.");
      }
      final id = cuerpo["id"] as int;
      fase(FaseEjecucion.ejecutando, "Esperando a que OP_PROD la tome…");

      final inicio = DateTime.now();
      final limite = inicio.add(espera);
      while (DateTime.now().isBefore(limite)) {
        await Future.delayed(_intervaloConsulta);
        final r = await ApiClient.enviar(() async => http
            .get(Uri.parse("${AppConfig.apiBaseUrl}/comandos/$id"), headers: await _headers())
            .timeout(_timeoutHttp, onTimeout: () => throw TimeoutException("El servidor no respondió a tiempo.")));
        final c = _decodificar(r);
        final estado = (c["estado"] ?? "").toString();
        if (estado == "pendiente") continue;
        if (estado == "en_curso") {
          final seg = DateTime.now().difference(inicio).inSeconds;
          fase(FaseEjecucion.ejecutando, "OP_PROD lo está ejecutando… ${seg}s");
          continue;
        }
        final resultado = ResultadoComando(
          id: id,
          estado: estado,
          resultado: (c["resultado"] as Map<String, dynamic>?) ?? const {},
          error: c["error"]?.toString(),
        );
        if (!resultado.ok) {
          throw ComandoFallidoException(resultado.error ?? "La orden terminó con error.");
        }
        if (anunciarFinal) {
          final mensaje = resultado.resultado["mensaje"]?.toString();
          fase(FaseEjecucion.listo, (mensaje == null || mensaje.isEmpty) ? "Listo." : mensaje);
        }
        return resultado;
      }
      throw ComandoFallidoException("OP_PROD no respondió en ${espera.inSeconds} s. Probá de nuevo.");
    } catch (e) {
      fase(FaseEjecucion.error, e is ComandoFallidoException ? e.mensaje : e.toString());
      rethrow;
    }
  }
}
