import "package:flutter/material.dart";

import "../models/alerta_infra.dart";
import "../screens/infraestructura_screen.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "fondo_app.dart";
import "titulo_seccion.dart";

/// En Alertas: las alarmas de infraestructura (congestión en Netezza). Si hay
/// una activa va en rojo con botón a Infraestructura; si no, una línea en verde.
/// Debajo, lo último del historial (se abrió, recordatorios, se normalizó).
class SeccionAlertasInfra extends StatelessWidget {
  const SeccionAlertasInfra({super.key, required this.datos, this.ahora});

  final AlertasInfra? datos;
  final DateTime Function()? ahora;

  static const maximoEventos = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final d = datos;
    if (d == null) return const SizedBox.shrink();
    final ahora = this.ahora?.call() ?? DateTime.now();
    final eventos = d.eventos.take(maximoEventos).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSeccion(
          "Infraestructura",
          accion: d.activas.isEmpty ? null : const PillEstado("En vivo", color: StatusColors.critico, icono: Icons.circle),
        ),
        const SizedBox(height: 10),
        if (d.activas.isEmpty)
          Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 18, color: StatusColors.exitoso),
              const SizedBox(width: 8),
              Expanded(
                child: Text("Netezza sin congestión ahora",
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
              ),
            ],
          )
        else
          for (final a in d.activas)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Vidrio(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
                color: StatusColors.critico.withValues(alpha: 0.10),
                borderColor: StatusColors.critico.withValues(alpha: 0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CajaIcono(Icons.storage_rounded, color: StatusColors.critico),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.titulo, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                              if (a.abiertaEn != null)
                                Text(
                                  "Desde ${fechaAmigable(a.abiertaEn!, ahora: ahora)} · hace "
                                  "${duracionCorta(ahora.difference(a.abiertaEn!).inSeconds)}",
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (a.mensaje.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(a.mensaje, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: Key("ver_infra_${a.clave}"),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const InfraestructuraScreen()),
                        ),
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: const Text("Ver bloqueos en Infraestructura"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (eventos.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Eyebrow("Últimos avisos de infraestructura"),
          const SizedBox(height: 6),
          for (final e in eventos) _FilaEvento(evento: e, ahora: ahora),
        ],
      ],
    );
  }
}

class _FilaEvento extends StatelessWidget {
  const _FilaEvento({required this.evento, required this.ahora});

  final EventoInfra evento;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (icono, color) = switch (evento.tipo) {
      "abre" => (Icons.notifications_active_rounded, StatusColors.critico),
      "sigue" => (Icons.update_rounded, StatusColors.advertencia),
      _ => (Icons.check_circle_outline_rounded, StatusColors.exitoso),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(evento.titulo, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (evento.mensaje.isNotEmpty)
                  Text(evento.mensaje,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(fechaAmigable(evento.creadoEn, ahora: ahora),
              style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline)),
        ],
      ),
    );
  }
}
