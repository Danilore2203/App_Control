import "package:flutter/material.dart";

import "../models/ra_archivo.dart";
import "../services/ejecucion_actual.dart";
import "../services/ra_service.dart";
import "../services/sesion_actual.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "../widgets/detalle_ra_sheet.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/fondo_app.dart";
import "../widgets/indicador_ejecucion.dart";
import "../widgets/titulo_seccion.dart";

/// Monitor RA como en la web: contadores por estado, la lista de archivos
/// (ultima carga de cada uno) y, para administradores, «Actualizar ahora»,
/// que corre en OP_PROD la misma sincronizacion FTP -> MySQL que el boton
/// de la web y muestra el avance en la barra flotante.
class RaScreen extends StatefulWidget {
  const RaScreen({super.key});

  @override
  State<RaScreen> createState() => _RaScreenState();
}

class _RaScreenState extends State<RaScreen> {
  static const _titulo = "Actualizar RA";

  final _servicio = RaService();
  late Future<RaMonitor> _future;
  RaMonitor? _monitor;
  String? _filtroColor; // null = todos
  bool _actualizando = false;
  RaActualizacion? _ultima;

  @override
  void initState() {
    super.initState();
    // Sin permisos no se pide nada: el backend lo rechazaria igual.
    _future = SesionActual.esAdmin ? _cargar() : Future.value(const RaMonitor(filas: [], resumen: {}));
  }

  Future<RaMonitor> _cargar() async {
    final m = await _servicio.obtenerMonitor();
    if (mounted) setState(() => _monitor = m);
    return m;
  }

  void _recargar() => setState(() => _future = _cargar());

  Future<void> _actualizar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Actualizar RA ahora?"),
        content: const Text(
          "OP_PROD baja los archivos de cada FTP configurado y los carga en MySQL, "
          "igual que «Actualizar» en el Monitor RA de la web. Puede tardar varios minutos.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Actualizar")),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _actualizando = true);
    try {
      final r = await _servicio.actualizarTodo(titulo: _titulo);
      if (!mounted) return;
      final errores = r.conError;
      EjecucionActual.mostrar(EstadoEjecucion(
        titulo: _titulo,
        detalle: "${r.mensaje} (${_duracion(r.duracionSeg)})",
        fase: errores == 0 ? FaseEjecucion.listo : FaseEjecucion.error,
        progreso: 1,
      ));
      setState(() {
        _ultima = r;
        _monitor = r.monitor;
        _future = Future.value(r.monitor);
      });
    } catch (_) {
      // La barra flotante ya muestra el error.
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  static String _duracion(int seg) {
    if (seg < 60) return "${seg}s";
    final m = seg ~/ 60;
    final s = seg % 60;
    return "${m}m ${s.toString().padLeft(2, "0")}s";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!SesionActual.esAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text("Monitor RA")),
        body: EstadoVacio(
          icono: Icons.lock_outline_rounded,
          mensaje: "Solo administradores",
          detalle: "El Monitor RA está disponible solo para administradores.",
          colorIcono: colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Monitor RA"),
        actions: [
          IconButton(
            tooltip: "Recargar",
            onPressed: _recargar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<RaMonitor>(
        future: _future,
        builder: (context, snapshot) {
          final monitor = _monitor;
          if (monitor == null && snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (monitor == null && snapshot.hasError) {
            return EstadoVacio(
              icono: Icons.folder_off_outlined,
              mensaje: "No se pudo leer el monitor RA",
              detalle: snapshot.error.toString().replaceFirst("Exception: ", ""),
              colorIcono: colorScheme.error,
              onReintentar: _recargar,
            );
          }
          final m = monitor ?? const RaMonitor(filas: [], resumen: {});
          final filas = _filtroColor == null
              ? m.filas
              : m.filas.where((f) => _filtroColor == "gray" ? (f.color == "gray" || f.color == "blue") : f.color == _filtroColor).toList();
          return RefreshIndicator(
            onRefresh: () async {
              _recargar();
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _TarjetaActualizar(
                  actualizando: _actualizando,
                  onActualizar: _actualizando ? null : _actualizar,
                  ultima: _ultima,
                ),
                const SizedBox(height: 14),
                _Resumen(
                  monitor: m,
                  seleccionado: _filtroColor,
                  onSeleccionar: (c) => setState(() => _filtroColor = _filtroColor == c ? null : c),
                ),
                const SizedBox(height: 16),
                TituloSeccion(
                  _filtroColor == null ? "Archivos" : "Archivos · ${_etiqueta(_filtroColor!)}",
                  accion: Text(
                    "${filas.length}",
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                if (filas.isEmpty)
                  EstadoVacio(
                    icono: Icons.inbox_outlined,
                    mensaje: "Sin archivos en este estado",
                    colorIcono: colorScheme.onSurfaceVariant,
                  )
                else
                  for (final f in filas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TarjetaArchivo(archivo: f),
                    ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const SafeArea(child: IndicadorEjecucion()),
    );
  }

  static String _etiqueta(String color) => switch (color) {
        "green" => "OK",
        "red" => "Error",
        "orange" => "Validación",
        _ => "En proceso",
      };
}


class _Resumen extends StatelessWidget {
  const _Resumen({required this.monitor, required this.seleccionado, required this.onSeleccionar});

  final RaMonitor monitor;
  final String? seleccionado;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tiles = <(String, String, int, IconData)>[
      ("green", "OK", monitor.cuenta("green"), Icons.check_circle_outline),
      ("red", "Error", monitor.cuenta("red"), Icons.error_outline),
      ("orange", "Validación", monitor.cuenta("orange"), Icons.rule_rounded),
      ("gray", "En proceso", monitor.enProceso, Icons.hourglass_bottom_rounded),
    ];
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: IndicadorTile(
                etiqueta: "Archivos",
                valor: "${monitor.total}",
                icono: Icons.folder_copy_outlined,
                onTap: seleccionado == null ? null : () => onSeleccionar(seleccionado!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: IndicadorTile(
                etiqueta: tiles[0].$2,
                valor: "${tiles[0].$3}",
                color: colorRa(tiles[0].$1, colorScheme),
                icono: tiles[0].$4,
                onTap: () => onSeleccionar(tiles[0].$1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 1; i < tiles.length; i++) ...[
              Expanded(
                child: Opacity(
                  opacity: seleccionado == null || seleccionado == tiles[i].$1 ? 1 : 0.55,
                  child: IndicadorTile(
                    etiqueta: tiles[i].$2,
                    valor: "${tiles[i].$3}",
                    color: colorRa(tiles[i].$1, colorScheme),
                    icono: tiles[i].$4,
                    onTap: () => onSeleccionar(tiles[i].$1),
                  ),
                ),
              ),
              if (i != tiles.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _TarjetaActualizar extends StatelessWidget {
  const _TarjetaActualizar({required this.actualizando, required this.onActualizar, required this.ultima});

  final bool actualizando;
  final VoidCallback? onActualizar;
  final RaActualizacion? ultima;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final u = ultima;
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CajaIcono(Icons.sync_rounded, color: acentoTinta(context), solido: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow("Administración"),
                    const SizedBox(height: 2),
                    Text("Sincronizar archivos RA", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Baja los archivos de cada FTP activo y los carga en MySQL; el monitor se relee al terminar.",
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onActualizar,
              icon: actualizando
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(actualizando ? "Actualizando…" : "Actualizar RA ahora"),
            ),
          ),
          if (u != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: Eyebrow("Última sincronización")),
                PillEstado(
                  u.conError == 0 ? "OK" : "${u.conError} con error",
                  color: u.conError == 0 ? StatusColors.exitoso : StatusColors.critico,
                  icono: u.conError == 0 ? Icons.check_rounded : Icons.error_outline,
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final r in u.resultados)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      r.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 15,
                      color: r.ok ? StatusColors.exitoso : StatusColors.critico,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "${r.nombre} · ${r.mensaje}",
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaArchivo extends StatelessWidget {
  const _TarjetaArchivo({required this.archivo});

  final RaArchivo archivo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tono = colorRa(archivo.color, colorScheme);
    final fecha = archivo.fechaHora == null ? null : (fechaCatalogo(archivo.fechaHora) ?? archivo.fechaHora);
    final detalle = <String>[
      if (archivo.proceso.isNotEmpty) archivo.proceso,
      if (fecha != null && fecha.isNotEmpty) fecha,
      if (archivo.tamano != null)
        "${formatearMiles(archivo.tamano!.round())} B${archivo.tamanoRef != null ? " · ref ${formatearMiles(archivo.tamanoRef!.round())} B" : ""}",
    ].join("  ·  ");
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      blur: 10,
      onTap: () => DetalleRaSheet.mostrar(context, archivo),
      child: Row(
        children: [
          CajaIcono(Icons.description_outlined, color: tono),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  archivo.archivo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (detalle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detalle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.3),
                  ),
                ],
                if (archivo.ruta != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.folder_open_rounded, size: 13, color: colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          archivo.ruta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.tech(color: colorScheme.outline, fontSize: 11, letterSpacing: 0.1),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PillEstado(archivo.estado, color: tono),
              const SizedBox(height: 6),
              Icon(Icons.chevron_right_rounded, size: 20, color: colorScheme.outline),
            ],
          ),
        ],
      ),
    );
  }
}
