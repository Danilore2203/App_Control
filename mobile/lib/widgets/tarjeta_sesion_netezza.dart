import "package:flutter/material.dart";

import "../models/netezza_sesion.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "../utils/sql_resumen.dart";
import "fondo_app.dart";
import "infra_comun.dart";
import "titulo_seccion.dart";

/// Una sesion de Netezza: quien es, que consulta hace (en pocas palabras),
/// cuanto pesa y, para administradores, abortar su transaccion o matarla.
class TarjetaSesionNetezza extends StatelessWidget {
  const TarjetaSesionNetezza({super.key, required this.sesion, this.onAbortar, this.onMatar, this.compacta = false});

  final NetezzaSesion sesion;
  final VoidCallback? onAbortar;
  final VoidCallback? onMatar;

  /// Idle: sin la linea de consulta ni las metricas.
  final bool compacta;

  (String, Color, IconData) _estado(ColorScheme colorScheme) {
    final estado = sesion.estado.toLowerCase();
    if (estado == "active") {
      return switch ((sesion.qscState ?? "").toLowerCase()) {
        "running" => ("Corriendo", StatusColors.info, Icons.bolt_rounded),
        "queued" => ("En cola", StatusColors.advertencia, Icons.hourglass_top_rounded),
        "pending" => ("Pendiente", StatusColors.advertencia, Icons.hourglass_top_rounded),
        _ => ("Activa", StatusColors.info, Icons.bolt_rounded),
      };
    }
    if (estado == "tx-idle") return ("Tx abierta", StatusColors.advertencia, Icons.lock_clock_outlined);
    return ("Idle", colorScheme.outline, Icons.pause_circle_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (estadoTxt, tono, icono) = _estado(colorScheme);
    final costo = sesion.qsEstcost;
    final pesada = costo != null && costo >= costoCritico;
    final hace = haceCuanto(sesion.conntime);
    final dataStage = (sesion.clientOsUsername ?? "").toLowerCase() == "dsadm";
    final os = (sesion.clientOsUsername ?? "").trim();
    final tieneConsulta = (sesion.command ?? "").trim().isNotEmpty;

    final chips = <Widget>[
      if (!compacta) ...[
        if (chipCosto(costo) != null) chipCosto(costo)!,
        if ((sesion.qsEstmem ?? 0) > 0) ChipDato(Icons.memory_rounded, "Mem ${formatearMiles(sesion.qsEstmem!.round())}", tooltip: "Memoria estimada"),
        if ((sesion.qsEstdisk ?? 0) > 0) ChipDato(Icons.storage_rounded, "Disco ${formatearMiles(sesion.qsEstdisk!.round())}", tooltip: "Disco estimado"),
      ],
      if ((sesion.ipaddr ?? "").isNotEmpty) ChipDato(Icons.lan_outlined, sesion.ipaddr!, tooltip: "IP del cliente"),
      if (dataStage)
        const ChipDato(Icons.settings_suggest_outlined, "DataStage", tooltip: "Usuario del sistema operativo: dsadm")
      else if (os.isNotEmpty && os.toLowerCase() != "default")
        ChipDato(Icons.badge_outlined, os, tooltip: "Usuario del sistema operativo"),
      if (hace != null) ChipDato(Icons.schedule_rounded, "hace $hace", tooltip: "Conectada ${sesion.conntime}"),
    ];

    return Vidrio(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      blur: 10,
      borderColor: pesada ? StatusColors.critico.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                CajaIcono(icono, color: tono, tamano: 36, tamanoIcono: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Sesión ${sesion.sessionId}",
                        style: AppTextStyles.tech(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [sesion.username, if ((sesion.dbname ?? "").isNotEmpty) sesion.dbname].join(" · "),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PillEstado(estadoTxt, color: tono),
              ],
            ),
          ),
          if (!compacta) ...[
            const SizedBox(height: 10),
            Padding(padding: const EdgeInsets.only(right: 6), child: LineaSql(sesion.command, tono: tono)),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          if (tieneConsulta || onAbortar != null || onMatar != null)
            // Wrap: en pantallas angostas los botones pasan a la linea de abajo.
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (tieneConsulta)
                  BotonAccion(
                    icono: Icons.code_rounded,
                    texto: "Ver consulta",
                    onTap: () => mostrarConsulta(
                      context,
                      titulo: "Sesión ${sesion.sessionId}",
                      subtitulo: [sesion.username, sesion.dbname, sesion.ipaddr].whereType<String>().join(" · "),
                      sql: sesion.command,
                    ),
                  ),
                if (onAbortar != null)
                  BotonAccion(icono: Icons.undo_rounded, texto: "Abortar", color: StatusColors.advertencia, onTap: onAbortar!),
                if (onMatar != null)
                  BotonAccion(icono: Icons.cancel_outlined, texto: "Matar", color: StatusColors.critico, onTap: onMatar!),
              ],
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}
