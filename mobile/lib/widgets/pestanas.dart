import "package:flutter/material.dart";

import "fondo_app.dart";

/// Selector segmentado sobre vidrio (General / Procesos / Tablas), igual al
/// del monitor web: cada opcion es (clave, etiqueta, cantidad).
class Pestanas extends StatelessWidget {
  const Pestanas({
    super.key,
    required this.seleccionada,
    required this.opciones,
    required this.onCambiar,
  });

  final String seleccionada;
  final List<(String, String, int)> opciones;
  final ValueChanged<String> onCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Vidrio(
      padding: const EdgeInsets.all(4),
      radius: 14,
      blur: 8,
      child: Row(
        children: [
          for (final (clave, etiqueta, cantidad) in opciones)
            Expanded(
              child: Material(
                color: clave == seleccionada ? colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onCambiar(clave),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          etiqueta,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: clave == seleccionada ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "$cantidad",
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: clave == seleccionada
                                ? colorScheme.onPrimary.withValues(alpha: 0.7)
                                : colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
