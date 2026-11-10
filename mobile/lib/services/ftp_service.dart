import "dart:async";

import "../models/reporte_ftp.dart";
import "comandos_service.dart";
import "ejecucion_actual.dart";
import "seguimiento_lanzamiento.dart";

/// Monitor FTP (los Excel que se abren en el servidor 208 y depositan su
/// reporte en el FTP) a traves de la cola de comandos. OP_PROD usa las mismas
/// funciones que /ftp en la web: abrir un libro respeta el maximo de libros
/// abiertos en el 208 y «Lanzar todos» es la «Cola de aperturas».
class FtpService {
  FtpService({ComandosService? comandos}) : _comandos = comandos ?? ComandosService();

  final ComandosService _comandos;

  static const intervaloConsulta = Duration(seconds: 8);
  static const maximoApertura = Duration(minutes: 30);
  static const maximoCola = Duration(minutes: 45);
  static const maxFallosSeguidos = 3;

  Future<ReportesMonitor> obtenerMonitor() async {
    final r = await _comandos.ejecutar("reportes.resumen");
    return ReportesMonitor.fromJson(r.resultado);
  }

  Future<CandidatosCola> candidatosCola() async {
    final r = await _comandos.ejecutar("reportes.cola.candidatos");
    return CandidatosCola.fromJson(r.resultado);
  }

  Future<ColaReportes> estadoCola() async {
    final r = await _comandos.ejecutar("reportes.cola.estado");
    return ColaReportes.fromJson(r.resultado);
  }

  Future<ColaReportes> detenerCola({required String titulo}) async {
    final r = await _comandos.ejecutar("reportes.cola.detener", titulo: titulo);
    return ColaReportes.fromJson(r.resultado);
  }

  /// «Abrir» de la web: pide al 208 que abra el libro y sigue la apertura
  /// hasta que el libro se cierra (corre sus macros y deposita el reporte).
  /// Termina cuando el 208 informa el final, o a los [maximoApertura].
  Future<void> abrirEnEl208(String archivo) async {
    final titulo = "Abrir $archivo";
    final r = await _comandos.ejecutar(
      "reportes.lanzar",
      payload: {"archivo": archivo},
      espera: const Duration(minutes: 3),
      titulo: titulo,
      anunciarFinal: false,
    );
    final jobId = (r.resultado["job_id"] ?? "").toString();
    if (jobId.isEmpty) {
      // El 208 acepto pero no devolvio seguimiento (version vieja del script).
      EjecucionActual.mostrar(EstadoEjecucion(
        titulo: titulo,
        detalle: (r.resultado["mensaje"] ?? "Enviado al 208.").toString(),
        fase: FaseEjecucion.listo,
      ));
      return;
    }
    await _seguirApertura(titulo: titulo, jobId: jobId);
  }

  Future<void> _seguirApertura({required String titulo, required String jobId}) async {
    final inicio = DateTime.now();
    final limite = inicio.add(maximoApertura);
    var fase = "";
    var fallos = 0;

    bool vigente() => EjecucionActual.notifier.value?.titulo == titulo;
    void corriendo() {
      if (!vigente()) return;
      final como = fase.isEmpty ? "" : " · $fase";
      EjecucionActual.mostrar(EstadoEjecucion(
        titulo: titulo,
        detalle: "Abierto en el 208… ${SeguimientoLanzamiento.duracion(DateTime.now().difference(inicio))}$como",
        fase: FaseEjecucion.ejecutando,
      ));
    }

    corriendo();
    final reloj = Timer.periodic(const Duration(seconds: 1), (_) => corriendo());
    try {
      while (DateTime.now().isBefore(limite)) {
        await Future.delayed(intervaloConsulta);
        if (!vigente()) return;
        Map<String, dynamic> e;
        try {
          e = (await _comandos.ejecutar("reportes.lanzar.estado", payload: {"job_id": jobId})).resultado;
          fallos = 0;
        } catch (err) {
          if (++fallos < maxFallosSeguidos) continue;
          if (vigente()) {
            EjecucionActual.mostrar(EstadoEjecucion(
              titulo: titulo,
              detalle: "Se abrió, pero no se pudo seguir: ${err is ComandoFallidoException ? err.mensaje : err}",
              fase: FaseEjecucion.error,
            ));
          }
          return;
        }
        if (!vigente()) return;
        fase = (e["fase"] ?? "").toString();
        if (e["terminado"] != true) continue;
        final tardo = SeguimientoLanzamiento.duracion(DateTime.now().difference(inicio));
        final ok = e["resultado"] == "OK";
        final mensaje = (e["mensaje"] ?? "").toString().trim();
        EjecucionActual.mostrar(EstadoEjecucion(
          titulo: titulo,
          detalle: ok
              ? "Se actualizó en $tardo."
              : "Terminó con error en $tardo${mensaje.isEmpty ? "" : ": $mensaje"}",
          fase: ok ? FaseEjecucion.listo : FaseEjecucion.error,
          progreso: 1,
        ));
        return;
      }
      if (vigente()) {
        EjecucionActual.mostrar(EstadoEjecucion(
          titulo: titulo,
          detalle: "Sigue abierto en el 208 después de ${SeguimientoLanzamiento.duracion(maximoApertura)}; revísalo en la web.",
          fase: FaseEjecucion.error,
        ));
      }
    } finally {
      reloj.cancel();
    }
  }

  /// «Iniciar cola»: OP_PROD abre los reportes elegibles de a pocos, cada uno
  /// a su hora. Se sigue el avance hasta que la cola termina o hasta
  /// [maximoCola]; despues la cola sigue sola en el servidor.
  Future<void> lanzarTodos({required String titulo}) async {
    final r = await _comandos.ejecutar("reportes.cola.iniciar", titulo: titulo, anunciarFinal: false);
    final cola = ColaReportes.fromJson(r.resultado);
    EjecucionActual.mostrar(estadoDeCola(titulo, cola));
    final limite = DateTime.now().add(maximoCola);
    while (DateTime.now().isBefore(limite)) {
      await Future.delayed(const Duration(seconds: 10));
      if (EjecucionActual.notifier.value?.titulo != titulo) return;
      ColaReportes c;
      try {
        c = await estadoCola();
      } catch (_) {
        continue; // una consulta fallida no corta el seguimiento
      }
      if (EjecucionActual.notifier.value?.titulo != titulo) return;
      final estado = estadoDeCola(titulo, c);
      EjecucionActual.mostrar(estado);
      if (estado.terminado) return;
    }
    if (EjecucionActual.notifier.value?.titulo == titulo) {
      EjecucionActual.mostrar(EstadoEjecucion(
        titulo: titulo,
        detalle: "La cola sigue en el servidor; mírala en Monitor FTP.",
        fase: FaseEjecucion.listo,
      ));
    }
  }

  /// Como se ve la cola en la barra flotante.
  static EstadoEjecucion estadoDeCola(String titulo, ColaReportes c) {
    final hechos = c.terminados + c.errores;
    final total = hechos + c.pendientes + c.abiertos;
    final progreso = total == 0 ? null : hechos / total;
    if (c.finalizada) {
      return EstadoEjecucion(
        titulo: titulo,
        detalle: c.errores == 0
            ? "Cola terminada: $hechos de $total sin errores."
            : "Cola terminada: $hechos de $total · ${c.errores} con error.",
        fase: c.errores == 0 ? FaseEjecucion.listo : FaseEjecucion.error,
        progreso: 1,
        completados: hechos,
        total: total,
      );
    }
    if (c.colgados > 0 || c.estado == "pausada") {
      return EstadoEjecucion(
        titulo: titulo,
        detalle: c.colgados > 0
            ? "Pausada: ${c.colgados} libro(s) colgado(s) en el 208. Revísalo en la web."
            : "Cola pausada. ${c.mensaje}".trim(),
        fase: FaseEjecucion.error,
        progreso: progreso,
        completados: hechos,
        total: total,
      );
    }
    final espera = c.abiertos == 0 && c.proximaHora != null ? " · espera las ${c.proximaHora}" : "";
    return EstadoEjecucion(
      titulo: titulo,
      detalle: "Abiertos ${c.abiertos}/${c.maxAbiertos} · en cola ${c.pendientes}$espera",
      fase: FaseEjecucion.progreso,
      progreso: progreso,
      completados: hechos,
      total: total,
    );
  }
}
