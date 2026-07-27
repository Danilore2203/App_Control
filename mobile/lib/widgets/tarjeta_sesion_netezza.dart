import "package:flutter/material.dart";

import "../models/netezza_sesion.dart";
import "../theme.dart";

class TarjetaSesionNetezza extends StatelessWidget {
  final NetezzaSesion sesion;
  final VoidCallback? onAbortar;

  const TarjetaSesionNetezza({super.key, required this.sesion, this.onAbortar});

  Color _color(ColorScheme colorScheme) {
    switch (sesion.estado.toLowerCase()) {
      case "active":
        return colorScheme.primary;
      case "idle":
        return colorScheme.onSurfaceVariant;
      default:
        return StatusColors.advertencia;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _color(colorScheme);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sesion.username,
                  style: AppTextStyles.tech(
                      color: colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(sesion.estado.toUpperCase(),
                    style: AppTextStyles.tech(color: color, fontSize: 9)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "SID ${sesion.sessionId} · ${sesion.dbname ?? '—'} · ${sesion.ipaddr ?? 'sin IP'}",
            style:
                TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11.5),
          ),
          if ((sesion.command ?? "").trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sesion.command!,
              style: AppTextStyles.tech(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _dato(colorScheme, "COSTO", sesion.qsEstcost),
              const SizedBox(width: 14),
              _dato(colorScheme, "MEM", sesion.qsEstmem),
              const SizedBox(width: 14),
              _dato(colorScheme, "DISCO", sesion.qsEstdisk),
              const Spacer(),
              if (onAbortar != null)
                TextButton.icon(
                  onPressed: onAbortar,
                  style: TextButton.styleFrom(
                      foregroundColor: StatusColors.critico),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text("ABORTAR",
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dato(ColorScheme colorScheme, String etiqueta, num? valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta,
            style: AppTextStyles.tech(
                color: colorScheme.onSurfaceVariant, fontSize: 8)),
        Text(
          valor == null ? "—" : valor.toStringAsFixed(0),
          style: AppTextStyles.tech(
              color: colorScheme.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
