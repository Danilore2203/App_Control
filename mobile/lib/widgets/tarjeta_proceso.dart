import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "titulo_seccion.dart";

/// Fila de un proceso o tabla en el monitor: icono de estado, nombre a todo
/// lo ancho y una linea con la fuente y que paso, en palabras («Falló hoy
/// 14:00», «Terminó ayer 15:15»). El estado se dice una sola vez (icono +
/// frase en su color); toda la fila abre el detalle.
class TarjetaProceso extends StatelessWidget {
  final Control control;
  final VoidCallback? onTap;

  const TarjetaProceso({super.key, required this.control, this.onTap});

  Color get _color {
    switch (control.categoria) {
      case "red":
        return StatusColors.critico;
      case "orange":
        return StatusColors.advertencia;
      case "green":
        return StatusColors.exitoso;
      case "blue":
        return StatusColors.info;
      case "tiempo":
        return StatusColors.neutral;
      default:
        return StatusColors.neutral;
    }
  }

  IconData get _icono {
    if (control.esTabla) {
      return switch (control.categoria) {
        "red" => Icons.table_view_outlined,
        "orange" => Icons.schedule_rounded,
        "green" => Icons.table_chart_outlined,
        "blue" => Icons.sync_rounded,
        _ => Icons.table_rows_outlined,
      };
    }
    return switch (control.categoria) {
      "red" => Icons.error_outline_rounded,
      "orange" => Icons.schedule_rounded,
      "green" => Icons.check_circle_outline_rounded,
      "blue" => Icons.sync_rounded,
      "tiempo" => Icons.hourglass_empty_rounded,
      _ => Icons.pause_circle_outline_rounded,
    };
  }

  /// (que paso, cuando) en palabras, como el monitor web lo cuenta.
  (String, String?) get _estado {
    // En medio de la frase: «Falló hoy 14:00», no «Falló Hoy 14:00».
    String? min(String? s) => s == null || s.isEmpty ? s : "${s[0].toLowerCase()}${s.substring(1)}";
    final fin = min(fechaCatalogo(control.horaFin ?? control.horaLog));
    final programado = min(fechaCatalogo(control.horaProgramada));
    final desde = min(fechaCatalogo(control.horaLog));
    switch (control.categoria) {
      case "red":
        return ("Falló", fin);
      case "orange":
        return ("Demorado", programado == null ? null : "· prog. $programado");
      case "green":
        return (control.esTabla ? "OK" : "Terminó", fin);
      case "blue":
        return ("Corriendo", desde == null ? null : "desde $desde");
      case "tiempo":
        return ("En tiempo", programado == null ? null : "· prog. $programado");
      default:
        final e = control.estado.trim();
        final texto = e.isEmpty ? "Sin ejecución" : "${e[0].toUpperCase()}${e.substring(1).toLowerCase()}";
        return (texto, fin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _color;
    final esCritico = control.categoria == "red";
    final core = control.core?.trim().toLowerCase() == "si";
    final (frase, cuando) = _estado;

    final extras = <String>[
      if (control.esTabla && control.cantidadFormateada != null) "${control.cantidadFormateada} reg.",
      if (control.esTabla && (control.layer ?? "").trim().isNotEmpty) control.layer!.trim(),
    ];

    return Material(
      color: esCritico ? Color.alphaBlend(color.withValues(alpha: 0.06), colorScheme.surfaceContainerHigh) : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: esCritico ? color.withValues(alpha: 0.35) : colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              CajaIcono(_icono, color: color, tamano: 38, tamanoIcono: 20),
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                          ),
                        ),
                        if (core) ...[
                          const SizedBox(width: 6),
                          const _Insignia("CORE", color: StatusColors.critico, icono: Icons.bolt_rounded),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.2),
                        children: [
                          TextSpan(
                            text: control.fuente,
                            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4, color: colorScheme.outline, fontSize: 11),
                          ),
                          const TextSpan(text: "  ·  "),
                          TextSpan(text: frase, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                          if (cuando != null) TextSpan(text: " $cuando"),
                          for (final e in extras) TextSpan(text: "  ·  $e"),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia(this.texto, {required this.color, required this.icono});

  final String texto;
  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            texto,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800, fontSize: 9.5, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
