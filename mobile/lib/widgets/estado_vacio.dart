import "package:flutter/material.dart";

/// Vista centrada para listas vacias o en error (icono + mensaje).
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String mensaje;
  final Color colorIcono;

  const EstadoVacio({super.key, required this.icono, required this.mensaje, required this.colorIcono});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: colorIcono),
            const SizedBox(height: 16),
            Text(mensaje, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
