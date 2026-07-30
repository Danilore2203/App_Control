import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";

/// Tarjeta de resumen: porcentaje de exito (anillo) + conteos por estado.
class SaludSistema extends StatelessWidget {
  final List<Control> controles;

  const SaludSistema({super.key, required this.controles});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // El backend reclasifica un DEMORADO (que ya paso su hora_fin) como
    // color "red" -no queda ningun control con color "orange" crudo-, asi
    // que contar por color solo hacia que "AVISOS" siempre diera 0 y
    // "FALLIDOS" mezclara demorados con errores reales. Se distingue por el
    // estado, mismo criterio que _bucketDe en dashboard_screen.dart.
    bool esDemorado(Control c) =>
        c.color == "red" && c.estado.toUpperCase() == "DEMORADO";

    final total = controles.length;
    final exitosos = controles.where((c) => c.color == "green").length;
    final fallidos =
        controles.where((c) => c.color == "red" && !esDemorado(c)).length;
    final avisos = controles.where(esDemorado).length;
    final porcentaje = total == 0 ? 0.0 : exitosos / total;

    final Color colorSalud;
    final String etiquetaSalud;
    if (total == 0) {
      colorSalud = colorScheme.onSurfaceVariant;
      etiquetaSalud = "SIN DATOS";
    } else if (porcentaje >= 0.9) {
      colorSalud = StatusColors.exitoso;
      etiquetaSalud = "OK";
    } else if (porcentaje >= 0.7) {
      colorSalud = StatusColors.advertencia;
      etiquetaSalud = "ATENCION";
    } else {
      colorSalud = StatusColors.critico;
      etiquetaSalud = "CRITICO";
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            Text(
              "SALUD DEL SISTEMA",
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: total == 0 ? 0 : porcentaje),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, valorAnimado, _) {
                return Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: colorSalud.withValues(alpha: 0.25),
                          blurRadius: 24,
                          spreadRadius: -4),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CircularProgressIndicator(
                          value: valorAnimado,
                          strokeWidth: 12,
                          backgroundColor: colorSalud.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(colorSalud),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            total == 0
                                ? "--"
                                : "${(valorAnimado * 100).round()}%",
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            etiquetaSalud,
                            style: TextStyle(
                                color: colorSalud, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Estadistica(
                    etiqueta: "TOTAL",
                    valor: total,
                    color: colorScheme.onSurface),
                _Estadistica(
                    etiqueta: "EXITOSOS",
                    valor: exitosos,
                    color: StatusColors.exitoso),
                _Estadistica(
                    etiqueta: "FALLIDOS",
                    valor: fallidos,
                    color: StatusColors.critico),
                _Estadistica(
                    etiqueta: "DEMORADOS",
                    valor: avisos,
                    color: StatusColors.advertencia),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Estadistica extends StatelessWidget {
  final String etiqueta;
  final int valor;
  final Color color;

  const _Estadistica(
      {required this.etiqueta, required this.valor, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          "$valor",
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          etiqueta,
          style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.85)),
        ),
      ],
    );
  }
}
