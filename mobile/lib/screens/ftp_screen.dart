import "dart:async";

import "package:flutter/material.dart";

import "../models/reporte_ftp.dart";
import "../services/comandos_service.dart";
import "../services/ftp_service.dart";
import "../services/sesion_actual.dart";
import "../theme.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/fondo_app.dart";
import "../widgets/indicador_ejecucion.dart";
import "../widgets/titulo_seccion.dart";

/// Monitor FTP como en la web (/ftp): cada reporte con su estado, los
/// contadores, la «Cola de aperturas» del 208 y, en el detalle de cada
/// reporte, «Abrir en el 208». Solo administradores.
class FtpScreen extends StatefulWidget {
  const FtpScreen({super.key});

  @override
  State<FtpScreen> createState() => _FtpScreenState();
}

class _FtpScreenState extends State<FtpScreen> {
  static const _tituloCola = "Lanzar todos los reportes";

  final _servicio = FtpService();
  final _busqueda = TextEditingController();
  late Future<ReportesMonitor> _future;
  ReportesMonitor? _monitor;
  String _filtro = "todos"; // todos | green | red | orange | gray | blue
  bool _ocupadoCola = false;

  /// Almacenados: se piden aparte la primera vez que se tocan (son miles).
  Future<ReportesMonitor>? _almacenados;

  void _seleccionar(String color) {
    setState(() {
      _filtro = (_filtro == color && color != "todos") ? "todos" : color;
      if (_filtro == "blue") _almacenados ??= _servicio.obtenerAlmacenados();
    });
  }

  @override
  void initState() {
    super.initState();
    _future = SesionActual.esAdmin ? _cargar() : Future.value(ReportesMonitor.vacio);
    _busqueda.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<ReportesMonitor> _cargar() async {
    final m = await _servicio.obtenerMonitor();
    if (mounted) setState(() => _monitor = m);
    return m;
  }

  void _recargar() => setState(() {
        _future = _cargar();
        _almacenados = _filtro == "blue" ? _servicio.obtenerAlmacenados() : null;
      });

  void _avisar(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? StatusColors.critico : null,
    ));
  }

  Future<bool> _confirmar(String titulo, Widget contenido, String accion) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: contenido,
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(accion)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _lanzarTodos() async {
    setState(() => _ocupadoCola = true);
    CandidatosCola cand;
    try {
      cand = await _servicio.candidatosCola();
    } catch (e) {
      _avisar(e is ComandoFallidoException ? e.mensaje : e.toString(), error: true);
      if (mounted) setState(() => _ocupadoCola = false);
      return;
    }
    if (!mounted) return;
    setState(() => _ocupadoCola = false);
    if (cand.elegibles.isEmpty) {
      _avisar("No hay reportes para lanzar ahora: la cola solo toma No depositado y En proceso de tipo ROBBY_REPORT, 24X7 u OP.");
      return;
    }
    final esperan = cand.elegibles.length - cand.yaTocan;
    final ok = await _confirmar(
      "¿Lanzar ${cand.elegibles.length} reporte(s)?",
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Se abren en el 208 de a ${_monitor?.cola.maxAbiertos ?? 2}, como «Iniciar cola» en la web. "
            "${cand.yaTocan} ya están en hora${esperan > 0 ? " y $esperan esperan su hora programada" : ""}.",
          ),
          if (cand.omitidos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "${cand.omitidos.length} no entran (otro tipo o ya abiertos).",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      "Lanzar",
    );
    if (!ok || !mounted) return;
    await _correrEnCola(() => _servicio.lanzarTodos(titulo: _tituloCola));
  }

  Future<void> _detenerCola() async {
    final ok = await _confirmar(
      "¿Cancelar los pendientes?",
      const Text("Se quitan los reportes que esperan en la cola. Los libros ya abiertos en el 208 terminan solos."),
      "Cancelar pendientes",
    );
    if (!ok || !mounted) return;
    await _correrEnCola(() => _servicio.detenerCola(titulo: "Cancelar pendientes"));
  }

  Future<void> _correrEnCola(Future<void> Function() accion) async {
    setState(() => _ocupadoCola = true);
    // El seguimiento de la cola puede durar mucho: la pantalla no lo espera.
    final hecho = Completer<void>();
    unawaited(accion().catchError((_) {}).whenComplete(() {
      if (!hecho.isCompleted) hecho.complete();
      if (mounted) _recargar();
    }));
    await Future.any([hecho.future, Future.delayed(const Duration(seconds: 6))]);
    if (mounted) {
      setState(() => _ocupadoCola = false);
      _recargar();
    }
  }

  Future<void> _abrir(ReporteFtp r) async {
    final ok = await _confirmar(
      "¿Abrir en el 208?",
      Text("Se abre «${r.archivo}» en el servidor 208. Corre sus macros, deposita el reporte en el FTP y se cierra solo."),
      "Abrir",
    );
    if (!ok || !mounted) return;
    unawaited(_servicio.abrirEnEl208(r.archivo).catchError((_) {}).whenComplete(() {
      if (mounted) _recargar();
    }));
  }

  void _verDetalle(ReporteFtp r) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _DetalleReporte(
        reporte: r,
        onAbrir: () {
          Navigator.of(context).pop();
          _abrir(r);
        },
      ),
    );
  }

  List<ReporteFtp> _filtradas(List<ReporteFtp> filas) {
    final q = _busqueda.text.trim().toLowerCase();
    return filas.where((f) {
      final porEstado = _filtro == "todos" ? f.color != "blue" : f.color == _filtro;
      if (!porEstado) return false;
      if (q.isEmpty) return true;
      bool hay(String? s) => (s ?? "").toLowerCase().contains(q);
      return hay(f.archivo) || hay(f.tipo) || hay(f.horaProgramada) || hay(f.horaDeposito);
    }).toList();
  }

  List<Widget> _lista(List<ReporteFtp> filas, {String? nota}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return [
      TituloSeccion(
        "Reportes · ${_etiqueta(_filtro)}",
        accion: Text(
          "${filas.length}",
          style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800),
        ),
      ),
      if (nota != null) ...[
        const SizedBox(height: 4),
        Text(nota, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
      ],
      const SizedBox(height: 8),
      if (filas.isEmpty)
        EstadoVacio(
          icono: Icons.inbox_outlined,
          mensaje: "Sin reportes para mostrar",
          colorIcono: colorScheme.onSurfaceVariant,
        )
      else
        for (final f in filas)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TarjetaReporte(reporte: f, onTap: () => _verDetalle(f)),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!SesionActual.esAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text("Monitor FTP")),
        body: EstadoVacio(
          icono: Icons.lock_outline_rounded,
          mensaje: "Solo administradores",
          detalle: "El Monitor FTP está disponible solo para administradores.",
          colorIcono: colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Monitor FTP"),
        actions: [
          IconButton(tooltip: "Recargar", onPressed: _recargar, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: FutureBuilder<ReportesMonitor>(
        future: _future,
        builder: (context, snapshot) {
          final monitor = _monitor;
          if (monitor == null && snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (monitor == null && snapshot.hasError) {
            return EstadoVacio(
              icono: Icons.cloud_off_outlined,
              mensaje: "No se pudo leer el Monitor FTP",
              detalle: snapshot.error.toString().replaceFirst("Exception: ", ""),
              colorIcono: colorScheme.error,
              onReintentar: _recargar,
            );
          }
          final m = monitor ?? ReportesMonitor.vacio;
          return RefreshIndicator(
            onRefresh: () async {
              _recargar();
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _TarjetaCola(
                  cola: m.cola,
                  ocupado: _ocupadoCola,
                  onLanzarTodos: _lanzarTodos,
                  onDetener: _detenerCola,
                ),
                const SizedBox(height: 14),
                _Contadores(
                  monitor: m,
                  seleccionado: _filtro,
                  onSeleccionar: _seleccionar,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _busqueda,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: "Buscar reporte, tipo u hora…",
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _busqueda.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _busqueda.clear),
                  ),
                ),
                const SizedBox(height: 16),
                if (_filtro == "blue")
                  FutureBuilder<ReportesMonitor>(
                    future: _almacenados,
                    builder: (context, s) {
                      if (s.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (s.hasError) {
                        return EstadoVacio(
                          icono: Icons.cloud_off_outlined,
                          mensaje: "No se pudieron leer los almacenados",
                          detalle: s.error.toString().replaceFirst("Exception: ", ""),
                          colorIcono: colorScheme.error,
                          onReintentar: () => setState(() => _almacenados = _servicio.obtenerAlmacenados()),
                        );
                      }
                      final a = s.data ?? ReportesMonitor.vacio;
                      final total = a.almacenadosTotal ?? a.filas.length;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _lista(
                          _filtradas(a.filas),
                          nota: total > a.filas.length ? "Los ${a.filas.length} más recientes de $total." : null,
                        ),
                      );
                    },
                  )
                else
                  ..._lista(_filtradas(m.filas)),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const SafeArea(child: IndicadorEjecucion()),
    );
  }
}

String _etiqueta(String color) => switch (color) {
      "green" => "OK",
      "red" => "No depositado",
      "orange" => "Demorado",
      "gray" => "En proceso",
      "blue" => "Almacenados",
      _ => "Todos",
    };

Color _colorFtp(String color, ColorScheme colorScheme) => switch (color) {
      "green" => StatusColors.exitoso,
      "red" => StatusColors.critico,
      "orange" => StatusColors.advertencia,
      "blue" => StatusColors.info,
      _ => colorScheme.outline,
    };

class _Contadores extends StatelessWidget {
  const _Contadores({required this.monitor, required this.seleccionado, required this.onSeleccionar});

  final ReportesMonitor monitor;
  final String seleccionado;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tiles = <(String, int, IconData)>[
      ("todos", monitor.todos, Icons.list_rounded),
      ("green", monitor.cuenta("green"), Icons.check_rounded),
      ("red", monitor.cuenta("red"), Icons.close_rounded),
      ("orange", monitor.cuenta("orange"), Icons.hourglass_bottom_rounded),
      ("gray", monitor.cuenta("gray"), Icons.settings_outlined),
      ("blue", monitor.cuenta("blue"), Icons.inventory_2_outlined),
    ];
    Widget tile((String, int, IconData) t) => Opacity(
          opacity: seleccionado == t.$1 || seleccionado == "todos" ? 1 : 0.55,
          child: IndicadorTile(
            etiqueta: _etiqueta(t.$1),
            valor: "${t.$2}",
            color: t.$1 == "todos" ? null : _colorFtp(t.$1, colorScheme),
            icono: t.$3,
            onTap: () => onSeleccionar(t.$1),
          ),
        );
    return Column(
      children: [
        for (var fila = 0; fila < 2; fila++) ...[
          if (fila > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: tile(tiles[fila * 3 + i])),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _TarjetaCola extends StatelessWidget {
  const _TarjetaCola({required this.cola, required this.ocupado, required this.onLanzarTodos, required this.onDetener});

  final ColaReportes cola;
  final bool ocupado;
  final VoidCallback onLanzarTodos;
  final VoidCallback onDetener;

  static (String, Color) _estado(ColaReportes c, ColorScheme colorScheme) => switch (c.estado) {
        "corriendo" => ("Corriendo", StatusColors.exitoso),
        "pausada" => ("Pausada", StatusColors.advertencia),
        "deteniendo" => ("Cerrando", StatusColors.advertencia),
        "terminada" => ("Terminada", StatusColors.info),
        _ => ("Inactiva", colorScheme.outline),
      };

  static (String, Color) _estadoItem(String estado, ColorScheme colorScheme) => switch (estado) {
        "pendiente" => ("En cola", colorScheme.outline),
        "abriendo" || "abierto" => ("Abierto", StatusColors.info),
        "colgado" => ("Colgado", StatusColors.critico),
        "terminado" => ("Listo", StatusColors.exitoso),
        "error" => ("Error", StatusColors.critico),
        _ => ("Cancelado", colorScheme.outline),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (texto, tono) = _estado(cola, colorScheme);
    final vivos = cola.vivos;
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CajaIcono(Icons.table_view_rounded, color: acentoTinta(context), solido: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow("Servidor 208"),
                    const SizedBox(height: 2),
                    Text("Cola de aperturas", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              PillEstado(texto, color: tono),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Abiertos ${cola.abiertos}/${cola.maxAbiertos} · en cola ${cola.pendientes} · listos ${cola.terminados}"
            "${cola.errores > 0 ? " · ${cola.errores} con error" : ""}"
            "${cola.proximaHora != null ? " · siguiente a las ${cola.proximaHora}" : ""}",
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.35),
          ),
          if (cola.mensaje.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(cola.mensaje, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: cola.sePuedeDetener
                ? OutlinedButton.icon(
                    onPressed: ocupado ? null : onDetener,
                    style: OutlinedButton.styleFrom(foregroundColor: StatusColors.critico),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text("Cancelar pendientes"),
                  )
                : FilledButton.icon(
                    onPressed: ocupado || cola.enMarcha ? null : onLanzarTodos,
                    icon: ocupado
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(ocupado ? "Consultando…" : "Lanzar todos"),
                  ),
          ),
          if (vivos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant),
            for (final it in vivos.take(6))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        it.horaProgramada == null ? it.archivo : "${it.horaProgramada}  ${it.archivo}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Builder(builder: (context) {
                      final (t, c) = _estadoItem(it.estado, colorScheme);
                      return PillEstado(t, color: c);
                    }),
                  ],
                ),
              ),
            if (vivos.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("y ${vivos.length - 6} más…", style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaReporte extends StatelessWidget {
  const _TarjetaReporte({required this.reporte, required this.onTap});

  final ReporteFtp reporte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tono = _colorFtp(reporte.color, colorScheme);
    final detalle = <String>[
      if (reporte.tipo.isNotEmpty) reporte.tipo,
      if (reporte.horaProgramada != null) "Prog. ${reporte.horaProgramada}",
      if (reporte.horaDeposito != null) "Dep. ${reporte.horaDeposito}",
      if (reporte.descargas3m != null) "${reporte.descargas3m} desc. 3M",
    ].join("  ·  ");
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      blur: 10,
      onTap: onTap,
      child: Row(
        children: [
          CajaIcono(Icons.description_outlined, color: tono),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reporte.archivo,
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
              ],
            ),
          ),
          const SizedBox(width: 10),
          PillEstado(_etiquetaEstado(reporte.color), color: tono),
        ],
      ),
    );
  }
}

String _etiquetaEstado(String color) => switch (color) {
      "green" => "OK",
      "red" => "No depositado",
      "orange" => "Demorado",
      "blue" => "Almacenado",
      _ => "En proceso",
    };

class _DetalleReporte extends StatelessWidget {
  const _DetalleReporte({required this.reporte, required this.onAbrir});

  final ReporteFtp reporte;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tono = _colorFtp(reporte.color, colorScheme);
    final datos = <(String, String?)>[
      ("Tipo", reporte.tipo.isEmpty ? null : reporte.tipo),
      ("Programada", reporte.horaProgramada),
      ("Depósito de hoy", reporte.horaDeposito),
      ("Última modificación", reporte.fechaModificacion),
      ("Tamaño", reporte.tamanioMb == null ? null : "${reporte.tamanioMb} MB"),
      ("Descargas 3 meses", reporte.descargas3m?.toString()),
      ("Ruta", reporte.ruta),
    ].where((d) => d.$2 != null && d.$2!.isNotEmpty).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(reporte.archivo, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                PillEstado(_etiquetaEstado(reporte.color), color: tono),
              ],
            ),
            const SizedBox(height: 14),
            for (final d in datos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(d.$1, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                    ),
                    Expanded(child: Text(d.$2!, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAbrir,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text("Abrir en el 208"),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Abre el libro en el servidor; al cerrarse se actualiza el depósito.",
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
