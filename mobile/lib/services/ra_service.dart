import "../models/ra_archivo.dart";
import "comandos_service.dart";

/// Monitor RA (archivos que llegan por FTP a MySQL) a traves de la cola de
/// comandos: OP_PROD lee la tabla silver y, para «Actualizar», corre la misma
/// sincronizacion que el boton del Monitor RA de la web.
class RaService {
  RaService({ComandosService? comandos}) : _comandos = comandos ?? ComandosService();

  final ComandosService _comandos;

  /// Cuanto puede tardar la sincronizacion completa (FTP + inserts por cada
  /// configuracion activa). OP_PROD responde recien al terminar.
  static const esperaActualizacion = Duration(minutes: 20);

  Future<RaMonitor> obtenerMonitor() async {
    final r = await _comandos.ejecutar("ra.resumen");
    return RaMonitor.fromJson(r.resultado);
  }

  /// Solo administradores (el backend lo exige). Publica el avance en la
  /// barra flotante con [titulo].
  Future<RaActualizacion> actualizarTodo({required String titulo}) async {
    final r = await _comandos.ejecutar(
      "ra.actualizar_todos",
      espera: esperaActualizacion,
      titulo: titulo,
      anunciarFinal: false,
    );
    return RaActualizacion.fromJson(r.resultado);
  }
}
