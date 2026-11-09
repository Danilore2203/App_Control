import "package:flutter/material.dart";

import "../services/ejecucion_actual.dart";
import "../theme.dart";
import "fondo_app.dart";
import "titulo_seccion.dart";

/// Tarjeta flotante con el avance de lo que la app pidio a OP_PROD: barra
/// indeterminada mientras se envia/ejecuta, barra con porcentaje cuando se
/// conoce el avance (actualizacion masiva) y el resultado al final. Se
/// oculta sola a los pocos segundos de terminar.
class IndicadorEjecucion extends StatelessWidget {
  const IndicadorEjecucion({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EstadoEjecucion?>(
      valueListenable: EjecucionActual.notifier,
      builder: (context, estado, _) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: estado == null
              ? const SizedBox(width: double.infinity, height: 0)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: _Tarjeta(estado: estado),
                ),
        );
      },
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.estado});

  final EstadoEjecucion estado;

  Color _tono(ColorScheme colorScheme) {
    switch (estado.fase) {
      case FaseEjecucion.listo:
        return StatusColors.exitoso;
      case FaseEjecucion.error:
        return StatusColors.critico;
      default:
        return colorScheme.primary;
    }
  }

  IconData get _icono {
    switch (estado.fase) {
      case FaseEjecucion.enviando:
        return Icons.cloud_upload_outlined;
      case FaseEjecucion.ejecutando:
      case FaseEjecucion.progreso:
        return Icons.bolt_rounded;
      case FaseEjecucion.listo:
        return Icons.check_circle_rounded;
      case FaseEjecucion.error:
        return Icons.error_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tono = _tono(colorScheme);
    final enCurso = !estado.terminado;
    final pct = estado.progreso;

    return Vidrio(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      radius: 18,
      borderColor: tono.withValues(alpha: 0.45),
      child: Row(
        children: [
          enCurso && pct == null
              ? SizedBox(
                  width: 36,
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: tono),
                  ),
                )
              : CajaIcono(_icono, color: tono, tamano: 36, tamanoIcono: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        estado.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (pct != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        estado.total != null ? "${estado.completados ?? 0}/${estado.total}" : "${(pct * 100).round()}%",
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tono,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  estado.detalle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: enCurso ? pct : 1,
                    minHeight: 5,
                    backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    color: tono,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: EjecucionActual.ocultar,
            icon: Icon(Icons.close, size: 18, color: colorScheme.onSurfaceVariant),
            tooltip: "Ocultar",
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
