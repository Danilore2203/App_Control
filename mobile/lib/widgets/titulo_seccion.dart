import "package:flutter/material.dart";

/// Título de sección en tipografía normal (no la monoespaciada "técnica"):
/// la monoespaciada queda para datos técnicos (nombres de procesos, horas),
/// no para la jerarquía de la pantalla, que así se lee más rápido.
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.texto, {super.key, this.accion});

  final String texto;

  /// Widget opcional alineado a la derecha (un contador, un botón "ver todo").
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          texto,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (accion != null) accion!,
      ],
    );
  }
}

/// Tarjeta chica de indicador: un número grande con su etiqueta, coloreada
/// según gravedad. Pensada para filas de 2-4 indicadores al tope de una
/// pantalla (abiertos ahora, hoy, etc.).
class IndicadorTile extends StatelessWidget {
  const IndicadorTile({
    super.key,
    required this.etiqueta,
    required this.valor,
    this.color,
    this.icono,
    this.onTap,
  });

  final String etiqueta;
  final String valor;
  final Color? color;
  final IconData? icono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final acento = color ?? colorScheme.onSurface;
    return Material(
      color: color == null
          ? colorScheme.surfaceContainerHigh
          : acento.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 14, color: acento),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      etiqueta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                valor,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: acento,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
