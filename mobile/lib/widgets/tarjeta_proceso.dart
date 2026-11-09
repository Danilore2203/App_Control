import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";
import "titulo_seccion.dart";

/// Tarjeta de un proceso o tabla: icono segun estado, nombre, fuente y una
/// linea de detalle (hora + estado para procesos; registros + capa para
/// tablas). Vidrio con borde fino y una barra de tono a la izquierda.
class TarjetaProceso extends StatelessWidget {
  final Control control;
  final VoidCallback? onTap;

  const TarjetaProceso({super.key, required this.control, this.onTap});

  Color _color(BuildContext context) {
    if (control.esDemorado) return StatusColors.advertencia;
    switch (control.color) {
      case "red":
        return StatusColors.critico;
      case "orange":
        return StatusColors.advertencia;
      case "green":
        return StatusColors.exitoso;
      case "blue":
        return StatusColors.info;
      default:
        return StatusColors.neutral;
    }
  }

  IconData get _icono {
    if (control.esTabla) {
      return control.color == "red" ? Icons.table_view_outlined : Icons.table_chart_outlined;
    }
    if (control.esDemorado) return Icons.schedule_rounded;
    switch (control.color) {
      case "red":
        return Icons.error_outline_rounded;
      case "orange":
        return Icons.schedule_rounded;
      case "green":
        return Icons.check_circle_outline_rounded;
      case "blue":
        return Icons.sync_rounded;
      default:
        return Icons.pause_circle_outline_rounded;
    }
  }

  String get _etiquetaHora {
    switch (control.color) {
      case "red":
        return "Falla";
      case "orange":
        return "Programado";
      case "green":
        return "Terminado";
      case "blue":
        return "Inicio";
      default:
        return "Último run";
    }
  }

  String? get _hora => control.horaFin ?? control.horaLog ?? control.horaProgramada;

  /// Linea de detalle: para procesos "Terminado: 06:12", para tablas la
  /// cantidad de registros y la capa (lo que trae el catalogo de tablas).
  String _detalle() {
    if (control.esTabla) {
      final partes = <String>[];
      final registros = control.cantidadFormateada;
      if (registros != null) partes.add("$registros reg.");
      final layer = control.layer?.trim();
      if (layer != null && layer.isNotEmpty) partes.add(layer);
      return partes.isEmpty ? "Tabla" : partes.join("  ·  ");
    }
    final hora = _hora;
    return hora != null ? "$_etiquetaHora: $hora" : _etiquetaHora;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _color(context);
    final detalle = _detalle();
    final esCritico = control.color == "red" && !control.esDemorado;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: esCritico ? color.withValues(alpha: 0.4) : colorScheme.outlineVariant,
        ),
        boxShadow: esCritico
            ? [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 18, spreadRadius: -4)]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              // Barra de tono: dentro de la tarjeta, con sus propias esquinas,
              // en vez de un borde izquierdo grueso que se cortaba feo con el
              // radio de la tarjeta.
              Container(
                width: 4,
                height: 38,
                margin: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: CajaIcono(_icono, color: color, tamano: 40, tamanoIcono: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              control.nombre,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _EtiquetaFuente(fuente: control.fuente),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          children: [
                            TextSpan(text: "$detalle  ·  "),
                            TextSpan(
                              text: control.estado,
                              style: TextStyle(color: color, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: colorScheme.outline, size: 20),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _EtiquetaFuente extends StatelessWidget {
  final String fuente;

  const _EtiquetaFuente({required this.fuente});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        fuente,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
