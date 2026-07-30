import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";

/// Tarjeta de un proceso: icono segun estado real, nombre, tecnologia
/// (fuente) y una linea de detalle con hora + estado.
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
        return Colors.grey;
    }
  }

  IconData get _icono {
    if (control.esDemorado) return Icons.schedule;
    switch (control.color) {
      case "red":
        return Icons.error_outline;
      case "orange":
        return Icons.schedule;
      case "green":
        return Icons.check_circle_outline;
      case "blue":
        return Icons.sync;
      default:
        return Icons.pause_circle_outline;
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
        return "Ultimo run";
    }
  }

  String? get _hora {
    return control.horaFin ?? control.horaLog ?? control.horaProgramada;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final hora = _hora;
    final esCritico = control.color == "red";

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHigh
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: esCritico
            ? [
                BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 14,
                    spreadRadius: -2)
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_icono, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              control.nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
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
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          children: [
                            TextSpan(
                                text: hora != null
                                    ? "$_etiquetaHora: $hora  ·  "
                                    : "$_etiquetaHora  ·  "),
                            TextSpan(
                              text: control.estado,
                              style: TextStyle(
                                  color: color, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20),
              ],
            ),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        fuente,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSecondaryContainer,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
