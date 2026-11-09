import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";
import "fondo_app.dart";
import "titulo_seccion.dart";

/// Tarjeta de resumen: anillo con el porcentaje de exito a la izquierda y,
/// a la derecha, el veredicto (OK / Atencion / Critico) con los conteos por
/// estado en una grilla compacta.
class SaludSistema extends StatelessWidget {
  final List<Control> controles;

  const SaludSistema({super.key, required this.controles});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final total = controles.length;
    final exitosos = controles.where((c) => c.color == "green").length;
    final fallidos = controles.where((c) => c.color == "red" && !c.esDemorado).length;
    final demorados = controles.where((c) => c.esDemorado).length;
    final enCurso = controles.where((c) => c.color == "blue").length;
    // Gris: "EN TIEMPO" (todavia no le toca correr; "En proceso" en el monitor
    // web) o sin ejecucion. No son exito ni falla.
    final enProceso = controles.where((c) => c.esEnTiempo).length;
    final sinEjecucion = controles.where((c) => c.color == "gray" && !c.esEnTiempo).length;
    final porcentaje = total == 0 ? 0.0 : exitosos / total;

    final Color colorSalud;
    final String etiquetaSalud;
    final IconData iconoSalud;
    if (total == 0) {
      colorSalud = colorScheme.outline;
      etiquetaSalud = "Sin datos";
      iconoSalud = Icons.remove_circle_outline;
    } else if (porcentaje >= 0.9) {
      colorSalud = StatusColors.exitoso;
      etiquetaSalud = "Estable";
      iconoSalud = Icons.check_circle_rounded;
    } else if (porcentaje >= 0.7) {
      colorSalud = StatusColors.advertencia;
      etiquetaSalud = "Atención";
      iconoSalud = Icons.warning_rounded;
    } else {
      colorSalud = StatusColors.critico;
      etiquetaSalud = "Crítico";
      iconoSalud = Icons.error_rounded;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Vidrio(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Eyebrow("Salud del sistema")),
                PillEstado(etiquetaSalud, color: colorSalud, icono: iconoSalud),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Anillo(porcentaje: porcentaje, color: colorSalud, vacio: total == 0),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _Dato(etiqueta: "OK", valor: exitosos, color: StatusColors.exitoso),
                          ),
                          Expanded(
                            child: _Dato(etiqueta: "Error", valor: fallidos, color: StatusColors.critico),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _Dato(etiqueta: "Demorado", valor: demorados, color: StatusColors.advertencia),
                          ),
                          Expanded(
                            child: _Dato(etiqueta: "Actualizando", valor: enCurso, color: StatusColors.info),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BarraApilada(
              total: total,
              segmentos: [
                (exitosos, StatusColors.exitoso),
                (enCurso, StatusColors.info),
                (demorados, StatusColors.advertencia),
                (fallidos, StatusColors.critico),
                (enProceso + sinEjecucion, StatusColors.neutral),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              total == 0
                  ? "Todavía no hay controles registrados"
                  : "$total elemento${total == 1 ? '' : 's'} monitoreado${total == 1 ? '' : 's'}"
                      "${enProceso > 0 ? ' · $enProceso en proceso' : ''}"
                      "${sinEjecucion > 0 ? ' · $sinEjecucion sin ejecución' : ''}",
              style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Anillo extends StatelessWidget {
  const _Anillo({required this.porcentaje, required this.color, required this.vacio});

  final double porcentaje;
  final Color color;
  final bool vacio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: vacio ? 0 : porcentaje),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, valor, _) {
        return Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 26, spreadRadius: -6),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 108,
                height: 108,
                child: CircularProgressIndicator(
                  value: valor,
                  strokeWidth: 9,
                  strokeCap: StrokeCap.round,
                  backgroundColor: color.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    vacio ? "--" : "${(valor * 100).round()}%",
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "ÉXITO",
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor, required this.color});

  final String etiqueta;
  final int valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 30,
          margin: const EdgeInsets.only(top: 3, right: 8),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$valor",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              etiqueta,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Barra horizontal con un segmento por estado, proporcional al total.
class _BarraApilada extends StatelessWidget {
  const _BarraApilada({required this.total, required this.segmentos});

  final int total;
  final List<(int, Color)> segmentos;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 7,
        child: total == 0
            ? ColoredBox(color: colorScheme.outlineVariant)
            : Row(
                children: [
                  for (final (cantidad, color) in segmentos)
                    if (cantidad > 0)
                      Expanded(
                        flex: cantidad,
                        child: Container(
                          margin: const EdgeInsets.only(right: 1.5),
                          color: color,
                        ),
                      ),
                  if (total - segmentos.fold<int>(0, (s, e) => s + e.$1) > 0)
                    Expanded(
                      flex: total - segmentos.fold<int>(0, (s, e) => s + e.$1),
                      child: ColoredBox(color: colorScheme.outlineVariant),
                    ),
                ],
              ),
      ),
    );
  }
}
