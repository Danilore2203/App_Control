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

/// Cuadro redondeado con un icono sobre fondo tenue del mismo tono: el
/// "leading" estandar de tarjetas, filas de menu y opciones.
class CajaIcono extends StatelessWidget {
  const CajaIcono(this.icono, {super.key, this.color, this.tamano = 40, this.tamanoIcono = 20, this.solido = false});

  final IconData icono;
  final Color? color;
  final double tamano;
  final double tamanoIcono;

  /// Fondo lleno del color (icono en onPrimary) en vez del tono al 14 %.
  final bool solido;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tono = color ?? colorScheme.primary;
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: solido ? tono : tono.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(tamano * 0.3),
        border: solido ? null : Border.all(color: tono.withValues(alpha: 0.18)),
      ),
      child: Icon(icono, color: solido ? colorScheme.onPrimary : tono, size: tamanoIcono),
    );
  }
}

/// Aviso en linea (error, advertencia o informacion) con fondo translucido
/// del tono, para formularios y pantallas de ajustes.
class MensajeInline extends StatelessWidget {
  const MensajeInline(this.texto, {super.key, this.color, this.icono = Icons.error_outline, this.onCerrar});

  final String texto;
  final Color? color;
  final IconData icono;
  final VoidCallback? onCerrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tono = color ?? StatusColors.critico;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: tono.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tono.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icono, color: tono, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          if (onCerrar != null)
            IconButton(
              onPressed: onCerrar,
              icon: Icon(Icons.close, size: 18, color: theme.colorScheme.onSurfaceVariant),
              visualDensity: VisualDensity.compact,
              tooltip: "Cerrar",
            ),
        ],
      ),
    );
  }
}

/// Fila de opcion dentro de una tarjeta vidrio: icono en caja, titulo,
/// descripcion y un control a la derecha (switch, boton, chevron...).
class FilaOpcion extends StatelessWidget {
  const FilaOpcion({
    super.key,
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.trailing,
    this.color,
    this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget? trailing;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      blur: 10,
      onTap: onTap,
      child: Row(
        children: [
          CajaIcono(icono, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitulo!,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!]
          else if (onTap != null) ...[
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, color: colorScheme.outline, size: 20),
          ],
        ],
      ),
    );
  }
}

/// Barra de progreso fina con esquinas redondeadas y color de tono.
class BarraProgreso extends StatelessWidget {
  const BarraProgreso({super.key, required this.valor, required this.color, this.alto = 5});

  final double valor;
  final Color color;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(alto),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: valor.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: alto,
          backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
          color: color,
        ),
      ),
    );
  }
}
