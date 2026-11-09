import "package:flutter/material.dart";

/// Vista centrada para listas vacias o en error: icono en un disco tenue,
/// mensaje y, si se pasa `onReintentar`, un boton (util en errores de red,
/// donde pull-to-refresh no siempre es obvio para el usuario).
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String mensaje;
  final String? detalle;
  final Color colorIcono;
  final VoidCallback? onReintentar;

  const EstadoVacio({
    super.key,
    required this.icono,
    required this.mensaje,
    required this.colorIcono,
    this.detalle,
    this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorIcono.withValues(alpha: 0.12),
                border: Border.all(color: colorIcono.withValues(alpha: 0.2)),
              ),
              child: Icon(icono, size: 34, color: colorIcono),
            ),
            const SizedBox(height: 18),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (detalle != null) ...[
              const SizedBox(height: 6),
              Text(
                detalle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (onReintentar != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text("Reintentar"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
