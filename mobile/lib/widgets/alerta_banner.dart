import "package:flutter/material.dart";

import "../theme.dart";

/// Banner rojo en la parte superior cuando hay procesos en estado critico
/// (color rojo). Se puede cerrar; vuelve a aparecer si se recarga la lista.
class AlertaBanner extends StatefulWidget {
  final int cantidadCriticos;
  final List<String> fuentesAfectadas;
  final VoidCallback? onTap;

  const AlertaBanner({
    super.key,
    required this.cantidadCriticos,
    required this.fuentesAfectadas,
    this.onTap,
  });

  @override
  State<AlertaBanner> createState() => _AlertaBannerState();
}

class _AlertaBannerState extends State<AlertaBanner> {
  bool _cerrado = false;

  @override
  void didUpdateWidget(covariant AlertaBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cantidadCriticos != widget.cantidadCriticos) {
      _cerrado = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cerrado || widget.cantidadCriticos == 0) {
      return const SizedBox.shrink();
    }

    final texto = widget.fuentesAfectadas.isEmpty
        ? "${widget.cantidadCriticos} proceso(s) en estado crítico"
        : "${widget.cantidadCriticos} proceso(s) en estado crítico en ${widget.fuentesAfectadas.join(", ")}";

    // Pill translucida con tono rojo (como .do-hs-badge--err del monitor
    // web), en vez de una franja roja solida que tapaba la cabecera.
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Material(
        color: StatusColors.critico.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: StatusColors.critico.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: StatusColors.critico, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    texto,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant, size: 18),
                  onPressed: () => setState(() => _cerrado = true),
                  visualDensity: VisualDensity.compact,
                  tooltip: "Cerrar",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
