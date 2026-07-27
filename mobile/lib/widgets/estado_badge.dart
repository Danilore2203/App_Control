import "package:flutter/material.dart";

/// Etiqueta chica con fondo suave del color dado (para estado de un control
/// o nivel de una alerta).
class EstadoBadge extends StatelessWidget {
  final String texto;
  final Color color;

  const EstadoBadge({super.key, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        texto,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
