import "dart:async";

import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "detalle_proceso_sheet.dart";
import "fondo_app.dart";
import "titulo_seccion.dart";

/// «Corriendo ahora»: los procesos (o tablas) en ejecución en este momento,
/// con cuánto llevan. Se actualiza solo (el tiempo avanza cada 30 s y la
/// lista con cada lectura del catálogo). Tocar uno abre su detalle.
class CorriendoAhora extends StatefulWidget {
  const CorriendoAhora({
    super.key,
    required this.controles,
    required this.onVerTodos,
    this.titulo = "Corriendo ahora",
    this.ahora,
  });

  final List<Control> controles;
  final VoidCallback onVerTodos;
  final String titulo;

  /// Para las pruebas.
  final DateTime Function()? ahora;

  static const maximoVisibles = 5;

  /// Desde cuándo corre. Airflow manda la hora en UTC y DataStage/Pentaho en
  /// hora local (sin zona en ambos casos): para Airflow se toma la lectura que
  /// dé un tiempo transcurrido razonable.
  static DateTime? inicioDe(Control c, DateTime ahora) {
    final f = leerFechaCatalogo(c.horaLog);
    if (f == null) return null;
    if (c.fuente.toUpperCase() != "AIRFLOW") return f;
    final comoUtc = DateTime.utc(f.year, f.month, f.day, f.hour, f.minute, f.second).toLocal();
    final candidatos = [f, comoUtc].where((d) => !d.isAfter(ahora.add(const Duration(minutes: 2)))).toList()
      ..sort((a, b) => b.compareTo(a));
    return candidatos.isEmpty ? f : candidatos.first;
  }

  @override
  State<CorriendoAhora> createState() => _CorriendoAhoraState();
}

class _CorriendoAhoraState extends State<CorriendoAhora> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ahora = widget.ahora?.call() ?? DateTime.now();
    final corriendo = widget.controles.where((c) => c.categoria == "blue").toList()
      ..sort((a, b) {
        // Primero los que llevan más tiempo.
        final ia = CorriendoAhora.inicioDe(a, ahora);
        final ib = CorriendoAhora.inicioDe(b, ahora);
        if (ia == null && ib == null) return a.nombre.compareTo(b.nombre);
        if (ia == null) return 1;
        if (ib == null) return -1;
        return ia.compareTo(ib);
      });

    if (corriendo.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline_rounded, size: 16, color: colorScheme.outline),
            const SizedBox(width: 6),
            Text("Nada corriendo en este momento",
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final visibles = corriendo.take(CorriendoAhora.maximoVisibles).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Vidrio(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        borderColor: StatusColors.info.withValues(alpha: 0.45),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Pulso(),
                const SizedBox(width: 8),
                Text(widget.titulo, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                PillEstado("${corriendo.length}", color: StatusColors.info),
                const Spacer(),
                TextButton(
                  key: const Key("corriendo_ver_todos"),
                  onPressed: widget.onVerTodos,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(corriendo.length > visibles.length ? "Ver los ${corriendo.length}" : "Ver en la lista"),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final c in visibles) _Fila(control: c, ahora: ahora),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.control, required this.ahora});

  final Control control;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final c = control;
    final inicio = CorriendoAhora.inicioDe(c, ahora);
    final lleva = inicio == null ? null : duracionCorta(ahora.difference(inicio).inSeconds);
    final desde = inicio == null || c.fuente.toUpperCase() == "AIRFLOW"
        ? null
        : "desde ${inicio.hour.toString().padLeft(2, "0")}:${inicio.minute.toString().padLeft(2, "0")}";
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => mostrarDetalleProceso(context, c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(
                    [c.fuente, if (desde != null) desde].join(" · "),
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              lleva ?? "en curso",
              style: theme.textTheme.labelLarge?.copyWith(
                color: StatusColors.info,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Punto azul que late: «esto está pasando ahora».
class _Pulso extends StatefulWidget {
  const _Pulso();

  @override
  State<_Pulso> createState() => _PulsoState();
}

class _PulsoState extends State<_Pulso> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(color: StatusColors.info, shape: BoxShape.circle),
      ),
    );
  }
}
