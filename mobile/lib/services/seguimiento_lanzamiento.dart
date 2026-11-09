import "dart:async";

import "comandos_service.dart";
import "ejecucion_actual.dart";

/// Despues de «Ejecutar ahora»: cronometro desde que OP_PROD lanzo el proceso
/// y, al terminar, cuanto tardo y como quedo.
///
/// OP_PROD responde al lanzamiento al instante (el proceso recien empieza);
/// aca se le pregunta cada [intervaloConsulta] con `procesos.lanzar.estado`
/// y entre consultas el cronometro avanza solo, cada segundo. El tiempo se
/// cuenta en el reloj del telefono desde que llego la respuesta del
/// lanzamiento; la duracion final la da OP_PROD (reloj del servidor) y si no
/// viene se usa la local.
class SeguimientoLanzamiento {
  SeguimientoLanzamiento({ComandosService? comandos}) : _comandos = comandos ?? ComandosService();

  final ComandosService _comandos;

  static const intervaloConsulta = Duration(seconds: 10);
  static const maximo = Duration(minutes: 45);
  static const maxFallosSeguidos = 3;

  /// «48s», «3m 05s», «1h 02m 09s».
  static String duracion(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String dos(int n) => n.toString().padLeft(2, "0");
    if (h > 0) return "${h}h ${dos(m)}m ${dos(s)}s";
    if (m > 0) return "${m}m ${dos(s)}s";
    return "${s}s";
  }

  /// Texto final y si fue bien, a partir de lo que devuelve `procesos.lanzar.estado`.
  /// `local` es lo que midio el telefono, por si OP_PROD no trae `duracion_seg`.
  static (String, bool) resumenFinal(Map<String, dynamic> estado, Duration local) {
    final seg = (estado["duracion_seg"] as num?)?.toInt();
    final tardo = duracion(seg != null ? Duration(seconds: seg) : local);
    final resultado = (estado["resultado"] ?? "").toString().toUpperCase();
    final proceso = (estado["estado_proceso"] ?? "").toString().toUpperCase();
    final cola = proceso.isEmpty ? "" : " · el proceso quedó en $proceso";
    if (resultado == "OK") return ("Terminó en $tardo$cola.", true);
    final mensaje = (estado["mensaje"] ?? "").toString().trim();
    final como = resultado.isEmpty ? "error" : resultado;
    return ("Terminó con $como en $tardo${mensaje.isEmpty ? "" : ": $mensaje"}", false);
  }

  /// Sigue la corrida hasta que termine (o hasta [maximo]) publicando en
  /// [EjecucionActual]. Se corta solo si el usuario cerro la barra o empezo
  /// otra accion. `lanzadoEnServidor` es el `lanzado_en` que devolvio OP_PROD
  /// y vuelve tal cual en cada consulta.
  Future<void> seguir({
    required String titulo,
    required String nombre,
    required String lanzadoEnServidor,
    DateTime? lanzadoEnLocal,
    /// Corrida real de DataStage (OP_PROD la devuelve en `run_id`): el estado
    /// se sigue por ese id, con el resultado y el log del job al terminar.
    String? runId,
  }) async {
    final inicio = lanzadoEnLocal ?? DateTime.now();
    final limite = inicio.add(maximo);
    var extra = "";
    var fallosSeguidos = 0;

    bool vigente() => EjecucionActual.notifier.value?.titulo == titulo;
    void corriendo() {
      if (!vigente()) return;
      EjecucionActual.mostrar(EstadoEjecucion(
        titulo: titulo,
        detalle: "Ejecutando… ${duracion(DateTime.now().difference(inicio))}$extra",
        fase: FaseEjecucion.ejecutando,
      ));
    }

    EjecucionActual.mostrar(EstadoEjecucion(titulo: titulo, detalle: "Ejecutando… 0s", fase: FaseEjecucion.ejecutando));
    final reloj = Timer.periodic(const Duration(seconds: 1), (_) => corriendo());
    try {
      while (DateTime.now().isBefore(limite)) {
        await Future.delayed(intervaloConsulta);
        if (!vigente()) return;
        Map<String, dynamic> estado;
        try {
          estado = (await _comandos.ejecutar(
            "procesos.lanzar.estado",
            payload: {
              "nombre": nombre,
              "lanzado_en": lanzadoEnServidor,
              if (runId != null && runId.isNotEmpty) "run_id": runId,
            },
          ))
              .resultado;
          fallosSeguidos = 0;
        } catch (e) {
          // Una consulta fallida no corta el cronometro; tres seguidas si (p.ej. el
          // backend de App_Control todavia no conoce el comando): se avisa y se para.
          if (++fallosSeguidos < maxFallosSeguidos) continue;
          if (vigente()) {
            final motivo = e is ComandoFallidoException ? e.mensaje : e.toString();
            EjecucionActual.mostrar(EstadoEjecucion(
              titulo: titulo,
              detalle: "Se lanzó, pero no se pudo seguir la corrida: $motivo",
              fase: FaseEjecucion.error,
            ));
          }
          return;
        }
        if (!vigente()) return;
        if (estado["corriendo"] == true) {
          final proceso = (estado["estado_proceso"] ?? "").toString();
          extra = proceso.isEmpty ? "" : " · proceso en $proceso";
          continue;
        }
        final (texto, ok) = resumenFinal(estado, DateTime.now().difference(inicio));
        EjecucionActual.mostrar(EstadoEjecucion(
          titulo: titulo,
          detalle: texto,
          fase: ok ? FaseEjecucion.listo : FaseEjecucion.error,
          progreso: 1,
        ));
        return;
      }
      if (vigente()) {
        EjecucionActual.mostrar(EstadoEjecucion(
          titulo: titulo,
          detalle: "Sigue corriendo después de ${duracion(maximo)}; míralo en el monitor.",
          fase: FaseEjecucion.error,
        ));
      }
    } finally {
      reloj.cancel();
    }
  }
}
