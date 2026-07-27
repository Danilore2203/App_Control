import "package:flutter/material.dart";

import "../models/postgres_sesion.dart";
import "../theme.dart";

class TarjetaSesionPostgres extends StatelessWidget {
  final PostgresSesion sesion;
  final VoidCallback? onCancelar;

  const TarjetaSesionPostgres(
      {super.key, required this.sesion, this.onCancelar});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bloqueada = sesion.estaBloqueada;
    final activa = (sesion.estado ?? "").toLowerCase() == "active";
    final color = bloqueada
        ? StatusColors.critico
        : activa
            ? StatusColors.info
            : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: bloqueada
                ? StatusColors.critico.withValues(alpha: 0.5)
                : Colors.transparent),
        boxShadow: bloqueada
            ? [
                BoxShadow(
                    color: StatusColors.critico.withValues(alpha: 0.2),
                    blurRadius: 12)
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "PID ${sesion.pid} · ${sesion.username ?? '—'}",
                  style: AppTextStyles.tech(
                      color: colorScheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
              if (bloqueada)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: StatusColors.critico.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text("BLOQUEADA",
                      style: AppTextStyles.tech(
                          color: StatusColors.critico, fontSize: 9)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "${sesion.datname ?? '—'} · ${sesion.applicationName ?? 'sin app'} · ${sesion.clientAddr ?? 'sin IP'}",
            style:
                TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11.5),
          ),
          if ((sesion.waitEvent ?? "").trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text("Esperando: ${sesion.waitEvent}",
                style: TextStyle(
                    color: StatusColors.advertencia,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ],
          if (bloqueada) ...[
            const SizedBox(height: 4),
            Text(
              "Bloqueada por PID: ${sesion.pidsQueLaBloquean.join(', ')}",
              style: TextStyle(
                  color: StatusColors.critico,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ],
          if ((sesion.queryText ?? "").trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                sesion.queryText!,
                style: AppTextStyles.tech(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (onCancelar != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancelar,
                style:
                    TextButton.styleFrom(foregroundColor: StatusColors.critico),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text("CANCELAR",
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
