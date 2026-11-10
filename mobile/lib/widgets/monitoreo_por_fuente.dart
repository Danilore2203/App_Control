import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";
import "titulo_seccion.dart";

/// Fila de tarjetas, una por fuente (DataStage/Pentaho/Airflow...) mas una
/// de los procesos CORE: cuantos son, una barra con la mezcla de estados y,
/// en palabras, cuantos fallan o estan demorados. Tocar una filtra la lista.
bool esCore(Control control) => control.core?.trim().toLowerCase() == "si";

/// "proceso", "tabla" o "elemento" segun lo que agrupa la tarjeta (en la
/// vista General una fuente puede mezclar procesos y tablas).
String _unidad(List<Control> grupo) {
  final tablas = grupo.where((c) => c.esTabla).length;
  if (tablas == 0) return "proceso";
  if (tablas == grupo.length) return "tabla";
  return "elemento";
}

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
    final porFuente = <String, List<Control>>{};
    for (final control in controles) {
      porFuente.putIfAbsent(control.fuente, () => []).add(control);
    }
    if (porFuente.isEmpty) return const SizedBox.shrink();

    // Las que tienen errores primero: es lo que se viene a mirar.
    final fuentes = porFuente.keys.toList()
      ..sort((a, b) {
        final ea = porFuente[a]!.where((c) => c.categoria == "red").length;
        final eb = porFuente[b]!.where((c) => c.categoria == "red").length;
        return ea != eb ? eb.compareTo(ea) : a.compareTo(b);
      });
    final core = controles.where(esCore).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: TituloSeccion("Por fuente"),
        ),
        // Alto segun el contenido (no fijo): con letra grande del celular no se corta.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (core.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _TarjetaGrupo(
                      nombre: "CORE",
                      icono: Icons.bolt_rounded,
                      grupo: core,
                      unidad: "crítico",
                      seleccionada: coreSeleccionado,
                      onTap: onSeleccionarCore,
                    ),
                  ),
                for (final fuente in fuentes)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _TarjetaGrupo(
                      nombre: fuente,
                      grupo: porFuente[fuente]!,
                      unidad: _unidad(porFuente[fuente]!),
                      seleccionada: fuenteSeleccionada == fuente,
                      onTap: onSeleccionarFuente == null ? null : () => onSeleccionarFuente!(fuente),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TarjetaGrupo extends StatelessWidget {
  const _TarjetaGrupo({
    required this.nombre,
    required this.grupo,
    required this.unidad,
    this.icono,
    this.seleccionada = false,
    this.onTap,
  });

  final String nombre;
  final List<Control> grupo;
  final String unidad;
  final IconData? icono;
  final bool seleccionada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    int cuenta(String c) => grupo.where((x) => x.categoria == c).length;
    final ok = cuenta("green");
    final error = cuenta("red");
    final demorado = cuenta("orange");
    final corriendo = cuenta("blue");
    final resto = grupo.length - ok - error - demorado - corriendo;
    final total = grupo.length;
    final pctOk = total == 0 ? 0 : (ok * 100 / total).round();

    final (resumen, tono) = error > 0
        ? ("$error con error", StatusColors.critico)
        : demorado > 0
            ? ("$demorado demorado${demorado == 1 ? "" : "s"}", StatusColors.advertencia)
            : ("Todo OK", StatusColors.exitoso);

    return Material(
      color: seleccionada ? colorScheme.primary.withValues(alpha: 0.14) : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 164,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: seleccionada
                  ? colorScheme.primary.withValues(alpha: 0.7)
                  : (error > 0 ? StatusColors.critico.withValues(alpha: 0.35) : colorScheme.outlineVariant),
              width: seleccionada ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 15, color: tono),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                  ),
                  Text(
                    "$pctOk%",
                    style: theme.textTheme.labelMedium?.copyWith(color: tono, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _BarraMezcla(segmentos: [
                (ok, StatusColors.exitoso),
                (error, StatusColors.critico),
                (demorado, StatusColors.advertencia),
                (corriendo, StatusColors.info),
                (resto, colorScheme.outline.withValues(alpha: 0.5)),
              ]),
              const SizedBox(height: 14),
              const Spacer(),
              Text(
                resumen,
                style: theme.textTheme.labelLarge?.copyWith(color: tono, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 1),
              Text(
                "de $total $unidad${total == 1 ? "" : "s"}",
                style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra fina con la proporcion de cada estado (verde, rojo, ambar...).
class _BarraMezcla extends StatelessWidget {
  const _BarraMezcla({required this.segmentos});

  final List<(int, Color)> segmentos;

  @override
  Widget build(BuildContext context) {
    final visibles = segmentos.where((s) => s.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        // stretch: sin esto cada segmento (ColoredBox sin hijo) queda de alto 0 y no se ve.
        child: visibles.isEmpty
            ? ColoredBox(color: Theme.of(context).colorScheme.outlineVariant, child: const SizedBox.expand())
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < visibles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(flex: visibles[i].$1, child: ColoredBox(color: visibles[i].$2)),
                  ],
                ],
              ),
      ),
    );
  }
}
