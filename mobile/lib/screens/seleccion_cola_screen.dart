import "package:flutter/material.dart";

import "../models/reporte_ftp.dart";
import "../services/comandos_service.dart";
import "../services/ftp_service.dart";
import "../theme.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/titulo_seccion.dart";

/// «Iniciar cola» de la web: los reportes No depositados / En proceso que se
/// pueden abrir en el 208, para elegir cuáles lanzar (por tipo: ROBBY_REPORT,
/// 24X7, OP; por hora: ya es su hora, mañana, tarde) y lanzarlos todos juntos.
/// Devuelve con `Navigator.pop` la lista de archivos marcados.
class SeleccionColaScreen extends StatefulWidget {
  const SeleccionColaScreen({super.key, this.maxAbiertos = 2, this.servicio});

  final int maxAbiertos;

  /// Para las pruebas; normalmente null.
  final FtpService? servicio;

  @override
  State<SeleccionColaScreen> createState() => _SeleccionColaScreenState();
}

enum _FiltroHora { todos, ya, manana, tarde }

class _SeleccionColaScreenState extends State<SeleccionColaScreen> {
  late final FtpService _servicio = widget.servicio ?? FtpService();
  late Future<CandidatosCola> _candidatos = _cargar();

  /// Tipos que se muestran (los chips de arriba). Vacío = todavía no cargó.
  final Set<String> _tipos = {};
  final Set<String> _marcados = {};
  _FiltroHora _hora = _FiltroHora.todos;

  Future<CandidatosCola> _cargar() async {
    final c = await _servicio.candidatosCola();
    if (mounted) {
      setState(() {
        _tipos
          ..clear()
          ..addAll(c.elegibles.map((e) => e.tipo));
        _marcados
          ..clear()
          ..addAll(c.elegibles.map((e) => e.archivo));
      });
    }
    return c;
  }

  void _reintentar() => setState(() => _candidatos = _cargar());

  bool _pasaHora(CandidatoCola c, _FiltroHora f) => switch (f) {
        _FiltroHora.todos => true,
        _FiltroHora.ya => c.yaToca,
        _FiltroHora.manana => c.esDeManana,
        _FiltroHora.tarde => c.esDeTarde,
      };

  List<CandidatoCola> _visibles(CandidatosCola c) =>
      c.elegibles.where((e) => _tipos.contains(e.tipo) && _pasaHora(e, _hora)).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Lanzar reportes")),
      body: FutureBuilder<CandidatosCola>(
        future: _candidatos,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError && !snap.hasData) {
            final e = snap.error;
            return EstadoVacio(
              icono: Icons.cloud_off_rounded,
              mensaje: "No se pudo consultar qué reportes se pueden lanzar",
              detalle: e is ComandoFallidoException ? e.mensaje : e.toString(),
              colorIcono: colorScheme.error,
              onReintentar: _reintentar,
            );
          }
          final c = snap.data ?? const CandidatosCola(elegibles: [], omitidos: []);
          if (c.elegibles.isEmpty) {
            return EstadoVacio(
              icono: Icons.task_alt_rounded,
              mensaje: "No hay reportes No depositados ni En proceso para abrir",
              detalle: c.omitidos.isEmpty ? null : "${c.omitidos.length} no entran (otro tipo o ya abiertos).",
              colorIcono: StatusColors.exitoso,
            );
          }
          final visibles = _visibles(c);
          final marcadosVisibles = visibles.where((v) => _marcados.contains(v.archivo)).toList();
          final todosMarcados = visibles.isNotEmpty && marcadosVisibles.length == visibles.length;
          final tiposConCuenta = <String, int>{};
          for (final e in c.elegibles) {
            tiposConCuenta[e.tipo] = (tiposConCuenta[e.tipo] ?? 0) + 1;
          }
          final porTipo = c.elegibles.where((e) => _tipos.contains(e.tipo));
          int contar(_FiltroHora f) => porTipo.where((e) => _pasaHora(e, f)).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              MensajeInline(
                "Se abren en el 208 de a ${widget.maxAbiertos}, cada uno a su hora programada, como «Iniciar cola» "
                "en la web. Los que todavía no llegan a su hora esperan en la cola.",
                color: colorScheme.primary,
                icono: Icons.info_outline,
              ),
              const SizedBox(height: 14),
              const Eyebrow("Tipo"),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final t in tiposConCuenta.keys)
                    FilterChip(
                      key: Key("tipo_$t"),
                      label: Text("${t.isEmpty ? "Sin tipo" : t} ${tiposConCuenta[t]}"),
                      selected: _tipos.contains(t),
                      onSelected: (si) => setState(() => si ? _tipos.add(t) : _tipos.remove(t)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Eyebrow("Hora programada"),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (f, texto) in const [
                    (_FiltroHora.todos, "Todos"),
                    (_FiltroHora.ya, "Ya es su hora"),
                    (_FiltroHora.manana, "Mañana"),
                    (_FiltroHora.tarde, "Tarde"),
                  ])
                    ChoiceChip(
                      label: Text("$texto ${contar(f)}"),
                      selected: _hora == f,
                      onSelected: (_) => setState(() => _hora = f),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    key: const Key("marcar_todos"),
                    tristate: true,
                    value: visibles.isEmpty
                        ? false
                        : (todosMarcados ? true : (marcadosVisibles.isEmpty ? false : null)),
                    onChanged: visibles.isEmpty
                        ? null
                        : (_) => setState(() {
                              if (todosMarcados) {
                                _marcados.removeAll(visibles.map((v) => v.archivo));
                              } else {
                                _marcados.addAll(visibles.map((v) => v.archivo));
                              }
                            }),
                  ),
                  Expanded(
                    child: Text(
                      "${marcadosVisibles.length} de ${visibles.length} marcados",
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (visibles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text("Ningún reporte con esos filtros.",
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
                )
              else
                for (final v in visibles)
                  _FilaCandidato(
                    candidato: v,
                    marcado: _marcados.contains(v.archivo),
                    onCambiar: (si) => setState(() => si ? _marcados.add(v.archivo) : _marcados.remove(v.archivo)),
                  ),
              if (c.omitidos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text("No entran (${c.omitidos.length})",
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    children: [
                      for (final o in c.omitidos)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(o.archivo, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text([if (o.tipo.isNotEmpty) o.tipo, if (o.motivo != null) o.motivo!].join(" · ")),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<CandidatosCola>(
        future: _candidatos,
        builder: (context, snap) {
          final c = snap.data;
          if (c == null || c.elegibles.isEmpty) return const SizedBox.shrink();
          final elegidos = _visibles(c).where((v) => _marcados.contains(v.archivo)).toList();
          final esperan = elegidos.where((e) => !e.yaToca).length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key("lanzar_marcados"),
                  onPressed: elegidos.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(elegidos.map((e) => e.archivo).toList()),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    elegidos.isEmpty
                        ? "Marca al menos un reporte"
                        : "Lanzar ${elegidos.length} reporte(s)${esperan > 0 ? " · $esperan esperan su hora" : ""}",
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilaCandidato extends StatelessWidget {
  const _FilaCandidato({required this.candidato, required this.marcado, required this.onCambiar});

  final CandidatoCola candidato;
  final bool marcado;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final c = candidato;
    final tono = c.color == "red" ? StatusColors.critico : colorScheme.outline;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onCambiar(!marcado),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: marcado, onChanged: (v) => onCambiar(v ?? false)),
            SizedBox(
              width: 46,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  c.horaCorta ?? "—",
                  style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 12, letterSpacing: 0.2),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.archivo, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (c.tipo.isNotEmpty) PillEstado(c.tipo, color: colorScheme.onSurfaceVariant),
                        PillEstado(c.estado, color: tono),
                        if (!c.yaToca && c.horaCorta != null)
                          PillEstado("espera ${c.horaCorta}", color: StatusColors.advertencia, icono: Icons.schedule_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
