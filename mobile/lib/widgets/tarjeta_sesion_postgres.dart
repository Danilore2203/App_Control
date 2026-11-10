import "package:flutter/material.dart";

import "../models/postgres_sesion.dart";
import "../theme.dart";
import "../utils/sql_resumen.dart";
import "fondo_app.dart";
import "infra_comun.dart";
import "titulo_seccion.dart";

/// Una sesion de PostgreSQL: si esta bloqueada (y por quien), si bloquea a
/// otras, que consulta hace, que espera y desde cuando. Administradores:
/// cancelar la consulta.
class TarjetaSesionPostgres extends StatelessWidget {
  const TarjetaSesionPostgres({super.key, required this.sesion, this.onCancelar, this.bloqueaA = 0});

  final PostgresSesion sesion;
  final VoidCallback? onCancelar;

  /// Cuantas sesiones de la lista esperan a esta.
  final int bloqueaA;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final estado = (sesion.estado ?? "").toLowerCase();
    final bloqueada = sesion.estaBloqueada;
    final bloqueadora = bloqueaA > 0;
    final activa = estado == "active";
    final txAbierta = estado.startsWith("idle in transaction");

    final (estadoTxt, tono, icono) = bloqueada
        ? ("Bloqueada", StatusColors.critico, Icons.lock_clock_outlined)
        : bloqueadora
            ? ("Bloquea", StatusColors.critico, Icons.block_rounded)
            : activa
                ? ("Activa", StatusColors.info, Icons.bolt_rounded)
                : txAbierta
                    ? ("Tx abierta", StatusColors.advertencia, Icons.hourglass_bottom_rounded)
                    : ((sesion.estado ?? "—"), colorScheme.outline, Icons.pause_circle_outline_rounded);

    final enTx = haceCuanto(sesion.xactStart);
    final conectada = haceCuanto(sesion.backendStart);
    final espera = (sesion.waitEvent ?? "").trim();
    final app = (sesion.applicationName ?? "").trim();

    final chips = <Widget>[
      if (espera.isNotEmpty) ChipDato(Icons.hourglass_empty_rounded, espera, color: StatusColors.advertencia, tooltip: "Evento de espera"),
      if (enTx != null) ChipDato(Icons.timelapse_rounded, "tx $enTx", tooltip: "Transacción abierta desde ${sesion.xactStart}"),
      if (app.isNotEmpty) ChipDato(Icons.apps_rounded, app, tooltip: "Aplicación"),
      if ((sesion.clientAddr ?? "").isNotEmpty) ChipDato(Icons.lan_outlined, sesion.clientAddr!, tooltip: "IP del cliente"),
      if (conectada != null && enTx == null) ChipDato(Icons.schedule_rounded, "hace $conectada", tooltip: "Conectada ${sesion.backendStart}"),
    ];

    return Vidrio(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      blur: 10,
      borderColor: bloqueada || bloqueadora ? StatusColors.critico.withValues(alpha: 0.5) : null,
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
                        "PID ${sesion.pid}",
                        style: AppTextStyles.tech(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [sesion.username, sesion.datname].whereType<String>().where((s) => s.isNotEmpty).join(" · "),
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
          if (bloqueadora || bloqueada) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: StatusColors.critico.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: StatusColors.critico.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bloqueadora)
                      _LineaAviso(
                        icono: Icons.block_rounded,
                        texto: "Bloquea a $bloqueaA ${bloqueaA == 1 ? "sesión" : "sesiones"}",
                      ),
                    if (bloqueadora && bloqueada) const SizedBox(height: 4),
                    if (bloqueada)
                      _LineaAviso(
                        icono: Icons.lock_clock_outlined,
                        texto: "Espera a PID ${sesion.pidsQueLaBloquean.join(", ")}",
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.only(right: 6), child: LineaSql(sesion.queryText, tono: tono)),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          Row(
            children: [
              if ((sesion.queryText ?? "").trim().isNotEmpty)
                BotonAccion(
                  icono: Icons.code_rounded,
                  texto: "Ver consulta",
                  onTap: () => mostrarConsulta(
                    context,
                    titulo: "PID ${sesion.pid}",
                    subtitulo: [sesion.username, sesion.datname, sesion.clientAddr].whereType<String>().join(" · "),
                    sql: sesion.queryText,
                  ),
                ),
              const Spacer(),
              if (onCancelar != null)
                BotonAccion(icono: Icons.cancel_outlined, texto: "Cancelar", color: StatusColors.critico, onTap: onCancelar!),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineaAviso extends StatelessWidget {
  const _LineaAviso({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 15, color: StatusColors.critico),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: StatusColors.critico, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
