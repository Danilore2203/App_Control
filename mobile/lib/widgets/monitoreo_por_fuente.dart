import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";

/// Fila de tarjetas, una por cada fuente (DataStage/Pentaho/Airflow/Otro),
/// cada una con un medidor circular chico mostrando % de exito.
bool esCore(Control control) => control.core?.trim().toLowerCase() == "si";

class MonitoreoPorFuente extends StatelessWidget {
  final List<Control> controles;
  final String? fuenteSeleccionada;
  final ValueChanged<String>? onSeleccionarFuente;
  final bool coreSeleccionado;
  final VoidCallback? onSeleccionarCore;

  const MonitoreoPorFuente({
    super.key,
    required this.controles,
    this.fuenteSeleccionada,
    this.onSeleccionarFuente,
    this.coreSeleccionado = false,
    this.onSeleccionarCore,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final porFuente = <String, List<Control>>{};
    for (final control in controles) {
      porFuente.putIfAbsent(control.fuente, () => []).add(control);
    }

    if (porFuente.isEmpty) return const SizedBox.shrink();

    final fuentesOrdenadas = porFuente.keys.toList()..sort();
    final core = controles.where(esCore).toList();
    final coreFallas =
        core.where((c) => c.color == "red" || c.color == "orange").length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            "MONITOREO POR FUENTE",
            style: AppTextStyles.tech(
                color: colorScheme.onSurfaceVariant, fontSize: 10),
          ),
        ),
        SizedBox(
          height: 118,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (core.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _TarjetaCore(
                    total: core.length,
                    fallas: coreFallas,
                    seleccionada: coreSeleccionado,
                    onTap: onSeleccionarCore,
                  ),
                ),
              for (final fuente in fuentesOrdenadas)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _TarjetaFuente(
                    nombre: fuente,
                    total: porFuente[fuente]!.length,
                    porcentaje: porFuente[fuente]!.isEmpty
                        ? 0.0
                        : porFuente[fuente]!
                                .where((c) => c.color == "green")
                                .length /
                            porFuente[fuente]!.length,
                    seleccionada: fuenteSeleccionada == fuente,
                    onTap: onSeleccionarFuente == null
                        ? null
                        : () => onSeleccionarFuente!(fuente),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TarjetaCore extends StatelessWidget {
  final int total;
  final int fallas;
  final bool seleccionada;
  final VoidCallback? onTap;

  const _TarjetaCore({
    required this.total,
    required this.fallas,
    required this.seleccionada,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = fallas > 0 ? StatusColors.critico : StatusColors.exitoso;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 148,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: seleccionada ? colorScheme.primary : Colors.transparent,
              width: 1.4,
            ),
            boxShadow: fallas > 0
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.25),
                        blurRadius: 14,
                        spreadRadius: -3)
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Icons.bolt, color: color, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "CORE",
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 11.5),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                fallas > 0 ? "$fallas en falla" : "Todo OK",
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
              Text(
                "de $total críticos",
                style: TextStyle(
                    fontSize: 10, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaFuente extends StatelessWidget {
  final String nombre;
  final int total;
  final double porcentaje;
  final bool seleccionada;
  final VoidCallback? onTap;

  const _TarjetaFuente({
    required this.nombre,
    required this.total,
    required this.porcentaje,
    this.seleccionada = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = porcentaje >= 0.9
        ? StatusColors.exitoso
        : porcentaje >= 0.7
            ? StatusColors.advertencia
            : StatusColors.critico;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 148,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: seleccionada ? colorScheme.primary : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: porcentaje),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, valorAnimado, _) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: valorAnimado,
                              strokeWidth: 4,
                              backgroundColor: color.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation(color),
                            ),
                            Text(
                              "${(valorAnimado * 100).round()}",
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: color),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nombre,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                "$total proceso${total == 1 ? '' : 's'}",
                style: TextStyle(
                    fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
