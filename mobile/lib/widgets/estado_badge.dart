import "package:flutter/material.dart";

import "titulo_seccion.dart";

/// Etiqueta chica con fondo suave del color dado (estado de un control o
/// nivel de una alerta). Mismo dibujo que PillEstado, mantenido por
/// compatibilidad con las pantallas que ya lo usan.
class EstadoBadge extends StatelessWidget {
  final String texto;
  final Color color;

  const EstadoBadge({super.key, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => PillEstado(texto, color: color);
}
