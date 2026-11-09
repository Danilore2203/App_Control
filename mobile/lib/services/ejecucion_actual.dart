import "dart:async";

import "package:flutter/foundation.dart";

/// Fase de lo que se esta ejecutando en OP_PROD por pedido de la app.
enum FaseEjecucion { enviando, ejecutando, progreso, listo, error }

class EstadoEjecucion {
  final String titulo;
  final String detalle;
  final FaseEjecucion fase;

  /// Avance 0..1 cuando se conoce (actualizacion masiva); null = indeterminado.
  final double? progreso;
  final int? completados;
  final int? total;

  const EstadoEjecucion({
    required this.titulo,
    required this.detalle,
    required this.fase,
    this.progreso,
    this.completados,
    this.total,
  });

  bool get terminado => fase == FaseEjecucion.listo || fase == FaseEjecucion.error;

  EstadoEjecucion copiar({String? detalle, FaseEjecucion? fase, double? progreso, int? completados, int? total}) =>
      EstadoEjecucion(
        titulo: titulo,
        detalle: detalle ?? this.detalle,
        fase: fase ?? this.fase,
        progreso: progreso ?? this.progreso,
        completados: completados ?? this.completados,
        total: total ?? this.total,
      );
}

/// Lo que la app esta haciendo en OP_PROD ahora mismo, para mostrarlo como
/// una barra flotante en cualquier pantalla (ver IndicadorEjecucion). Una
/// sola ejecucion visible a la vez: la ultima que arranco.
class EjecucionActual {
  static final ValueNotifier<EstadoEjecucion?> notifier = ValueNotifier<EstadoEjecucion?>(null);
  static Timer? _ocultar;

  static void mostrar(EstadoEjecucion estado) {
    _ocultar?.cancel();
    notifier.value = estado;
    if (estado.terminado) {
      _ocultar = Timer(const Duration(seconds: 8), ocultar);
    }
  }

  static void actualizar(EstadoEjecucion Function(EstadoEjecucion actual) cambio) {
    final actual = notifier.value;
    if (actual == null) return;
    mostrar(cambio(actual));
  }

  static void ocultar() {
    _ocultar?.cancel();
    notifier.value = null;
  }
}
