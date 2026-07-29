import "package:flutter/material.dart";

/// Vista centrada para listas vacias o en error (icono + mensaje). Si se
/// pasa `onReintentar`, muestra ademas un boton (util en estados de error de
/// red, donde pull-to-refresh no siempre es obvio para el usuario).
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String mensaje;
  final Color colorIcono;
  final VoidCallback? onReintentar;

  const EstadoVacio({
    super.key,
    required this.icono,
    required this.mensaje,
    required this.colorIcono,
    this.onReintentar,
  });

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
            if (onReintentar != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh),
                label: const Text("Reintentar"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
