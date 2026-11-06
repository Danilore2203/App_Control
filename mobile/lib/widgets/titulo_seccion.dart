import "package:flutter/material.dart";

import "../theme.dart";
import "fondo_app.dart";

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
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (accion != null) accion!,
      ],
    );
  }
}

/// Etiqueta "eyebrow" del monitor web: chica, en mayúsculas, con tracking
/// ancho y color atenuado (.lt-kpi-lbl / .bt-eyebrow).
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.texto, {super.key, this.color});

  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      texto.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.colorScheme.outline,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        fontSize: 10.5,
      ),
    );
  }
}

/// Tarjeta de indicador como .lt-kpi de la web: vidrio translúcido, una
/// línea de color (el "tono") arriba, etiqueta eyebrow y número grande con
/// tracking apretado. Pensada para filas de 2-4 al tope de una pantalla.
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

  /// Tono del indicador (línea superior y número). Sin tono: neutro.
  final Color? color;
  final IconData? icono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tono = color ?? colorScheme.outline;
    return Vidrio(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 3, color: tono),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (icono != null) ...[
                      Icon(icono, size: 13, color: tono),
                      const SizedBox(width: 5),
                    ],
                    Expanded(child: Eyebrow(etiqueta)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  valor,
                  maxLines: 1,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: color ?? colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill de estado (.do-hs-badge): fondo del tono al 14 %, texto del tono.
class PillEstado extends StatelessWidget {
  const PillEstado(this.texto, {super.key, required this.color, this.icono});

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Atajo para el color "tinta" del acento (lima legible como texto sobre
/// fondo claro; en oscuro, el lima claro), como --pm-accent-ink.
Color acentoTinta(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? OpTokens.accentInkDark : OpTokens.accentInkLight;
