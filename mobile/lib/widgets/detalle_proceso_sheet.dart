import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../models/control.dart";
import "../services/ejecucion_actual.dart";
import "../services/seguimiento_lanzamiento.dart";
import "../services/sesion_actual.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "../screens/robby_screen.dart";
import "grafica_filas.dart";
import "titulo_seccion.dart";

/// Abre el detalle de un proceso (o tabla) como bottom sheet, con lo que el
/// catalogo realmente trae: estado, la corrida en una linea de tiempo
/// (programado, inicio, fin y cuanto tardo), los datos tecnicos y, para
/// administradores, las acciones.
Future<void> mostrarDetalleProceso(BuildContext context, Control control) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _DetalleProcesoSheet(control: control),
  );
}

class _DetalleProcesoSheet extends StatefulWidget {
  final Control control;

  const _DetalleProcesoSheet({required this.control});

  @override
  State<_DetalleProcesoSheet> createState() => _DetalleProcesoSheetState();
}

class _DetalleProcesoSheetState extends State<_DetalleProcesoSheet> {
  late Timer _reloj;
  DateTime _ahora = DateTime.now();
  String? _accionEnCurso;

  /// Ejecuta una accion en OP_PROD (lanzar el proceso, pausar/reanudar el
  /// DAG) tras confirmar. Solo administradores ven estos botones; el
  /// backend lo exige igual. Con `seguir`, despues del lanzamiento se queda
  /// siguiendo la corrida: cronometro desde que arranco y, al final, cuanto
  /// tardo (ver SeguimientoLanzamiento).
  Future<void> _accion(
    String clave,
    String titulo,
    String detalle,
    String tipo,
    Map<String, dynamic> payload, {
    bool seguir = false,
  }) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(detalle),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Confirmar")),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _accionEnCurso = clave);
    try {
      // El avance se ve en la barra flotante del monitor (IndicadorEjecucion)
      // y aca abajo mientras la hoja este abierta.
      await ejecutarYSeguir(tipo: tipo, payload: payload, titulo: titulo, seguir: seguir);
    } catch (_) {
      // El indicador ya muestra el error.
    } finally {
      if (mounted) setState(() => _accionEnCurso = null);
    }
  }

  Widget _botonesAccion(ColorScheme colorScheme) {
    if (!SesionActual.esAdmin || control.esTabla) return const SizedBox.shrink();
    final esAirflow = control.fuente.toUpperCase() == "AIRFLOW";
    final pausado = control.estado.toUpperCase() == "PAUSADO";
    Widget boton(String clave, IconData icono, String texto, VoidCallback onTap, {bool destacado = false}) {
      final ocupado = _accionEnCurso == clave;
      final icon = ocupado
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icono, size: 18);
      return destacado
          ? FilledButton.icon(onPressed: _accionEnCurso == null ? onTap : null, icon: icon, label: Text(texto))
          : OutlinedButton.icon(onPressed: _accionEnCurso == null ? onTap : null, icon: icon, label: Text(texto));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow("Acciones"),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: boton(
                  "lanzar",
                  Icons.play_arrow_rounded,
                  esAirflow ? "Disparar DAG" : "Ejecutar ahora",
                  () => _accion(
                    "lanzar",
                    esAirflow ? "Disparar ${control.nombre}" : "Ejecutar ${control.nombre}",
                    esAirflow
                        ? "Se crea una corrida manual del DAG en Airflow, como desde el monitor web."
                        : "Se lanza el proceso en ${control.fuente} a través del scheduler de OP, como desde la web.",
                    "procesos.lanzar",
                    {"nombre": control.nombre, "fuente": control.fuente, "ruta": control.ruta ?? ""},
                    seguir: !esAirflow,
                  ),
                  destacado: true,
                ),
              ),
              if (esAirflow) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: boton(
                    "pausa",
                    pausado ? Icons.play_circle_outline_rounded : Icons.pause_circle_outline_rounded,
                    pausado ? "Reanudar DAG" : "Pausar DAG",
                    () => _accion(
                      "pausa",
                      pausado ? "Reanudar ${control.nombre}" : "Pausar ${control.nombre}",
                      pausado
                          ? "El DAG vuelve a correr según su programación."
                          : "El DAG deja de correr hasta que lo reanudes.",
                      "airflow.pausar",
                      {"dag_id": control.nombre, "pausar": !pausado},
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Robby: ver si el proceso esta en la tabla de flujos ALFA e
          // insertarlo para que Robby lo corra (DataStage / Pentaho).
          if (!esAirflow) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key("abrir_robby"),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RobbyScreen(procesoInicial: control.nombre)),
                ),
                icon: const Icon(Icons.smart_toy_outlined, size: 18),
                label: const Text("Robby: verificar o insertar"),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Mientras la hoja esta abierta, el avance se ve aca mismo.
          ValueListenableBuilder<EstadoEjecucion?>(
            valueListenable: EjecucionActual.notifier,
            builder: (context, estado, _) {
              if (estado == null || _accionEnCurso == null && estado.terminado == false) {
                return Text(
                  "Lo ejecuta OP_PROD dentro de la red; tarda unos segundos.",
                  style: TextStyle(color: colorScheme.outline, fontSize: 11),
                );
              }
              final tono = switch (estado.fase) {
                FaseEjecucion.listo => StatusColors.exitoso,
                FaseEjecucion.error => StatusColors.critico,
                _ => colorScheme.primary,
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: estado.terminado ? 1 : estado.progreso,
                      minHeight: 5,
                      backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      color: tono,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    estado.detalle,
                    style: TextStyle(color: tono, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _ahora = DateTime.now());
    });
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  Control get control => widget.control;

  Color _color(ColorScheme colorScheme) {
    switch (control.categoria) {
      case "red":
        return StatusColors.critico;
      case "orange":
        return StatusColors.advertencia;
      case "green":
        return StatusColors.exitoso;
      case "blue":
        return StatusColors.info;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  String _hace(DateTime desde) {
    final diff = _ahora.difference(desde);
    if (diff.inSeconds < 0) return "recién";
    if (diff.inMinutes < 1) return "hace ${diff.inSeconds} s";
    return "hace ${duracionCorta(diff.inSeconds)}";
  }

  String? _sinVacio(String? valor) {
    if (valor == null || valor.trim().isEmpty) return null;
    return valor.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _color(colorScheme);
    final enEjecucion = control.categoria == "blue";
    final esTabla = control.esTabla;
    final ruta = _sinVacio(control.ruta);
    final version = _sinVacio(control.version);
    final layer = _sinVacio(control.layer);
    final esCoreProc = control.core?.trim().toLowerCase() == "si";
    final catalogo = esTabla ? "dataops_catalogo_tablas" : "dataops_catalogo_procesos";

    // La corrida (o la carga de la tabla) en una linea de tiempo.
    final tiempos = esTabla
        ? <(IconData, String, String?)>[
            (Icons.event_available_rounded, "Última carga", fechaCatalogo(control.ultimaFecha)),
            (Icons.schedule_rounded, "Programada", fechaCatalogo(control.horaProgramada)),
          ]
        : <(IconData, String, String?)>[
            (Icons.schedule_rounded, "Programado", fechaCatalogo(control.horaProgramada)),
            (Icons.play_circle_outline_rounded, "Inicio", fechaCatalogo(control.horaLog)),
            (Icons.flag_outlined, control.categoria == "red" ? "Falla" : "Fin", fechaCatalogo(control.horaFin)),
            (Icons.timer_outlined, "Duración", duracionEntre(control.horaLog, control.horaFin)),
          ];
    final datos = <(String, String, bool)>[
      if (esTabla && control.cantidadFormateada != null) ("Registros", control.cantidadFormateada!, false),
      if (layer != null) ("Capa", layer, false),
      if (version != null) ("Versión", "v$version", false),
      if (ruta != null) ("Ruta", ruta, true),
      ("Catálogo", catalogo, true),
      ("Snapshot", fechaAmigable(control.snapshotTs), false),
    ];

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Container(
          decoration: BoxDecoration(
            color: theme.bottomSheetTheme.backgroundColor ?? colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, -8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(esTabla ? "Tabla" : "Proceso"),
                          const SizedBox(height: 4),
                          // minLines 1: sin esto reserva el alto de 3 lineas aunque el nombre sea corto.
                          SelectableText(
                            control.nombre,
                            minLines: 1,
                            maxLines: 3,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              PillEstado(control.estado, color: color, icono: Icons.circle),
                              PillEstado(control.fuente, color: colorScheme.outline),
                              if (esCoreProc) const PillEstado("CORE", color: StatusColors.critico, icono: Icons.bolt_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Tarjeta(
                        borde: color.withValues(alpha: 0.35),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                _IconoEstado(color: color, animado: enEjecucion, colorScheme: colorScheme),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        control.estado,
                                        style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Última lectura ${_hace(control.snapshotTs)}",
                                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _BarraEstado(color: color, animada: enEjecucion),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Eyebrow(esTabla ? "Carga" : "Corrida"),
                      const SizedBox(height: 8),
                      _Tarjeta(
                        child: Column(
                          children: [
                            for (var i = 0; i < tiempos.length; i++)
                              _FilaTiempo(
                                icono: tiempos[i].$1,
                                etiqueta: tiempos[i].$2,
                                valor: tiempos[i].$3,
                                tono: tiempos[i].$2 == "Falla" ? StatusColors.critico : null,
                                conLinea: i < tiempos.length - 1,
                              ),
                          ],
                        ),
                      ),
                      if (esTabla) ...[
                        const SizedBox(height: 18),
                        const Eyebrow("Filas por día · últimos 40 días"),
                        const SizedBox(height: 8),
                        _Tarjeta(child: GraficaFilasPorDia(tabla: control.nombre)),
                      ],
                      const SizedBox(height: 18),
                      const Eyebrow("Datos"),
                      const SizedBox(height: 8),
                      _Tarjeta(
                        child: Column(
                          children: [
                            for (var i = 0; i < datos.length; i++) ...[
                              if (i > 0) Divider(height: 18, color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                              _FilaDato(etiqueta: datos[i].$1, valor: datos[i].$2, mono: datos[i].$3),
                            ],
                          ],
                        ),
                      ),
                      _botonesAccion(colorScheme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.child, this.borde});

  final Widget child;
  final Color? borde;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borde ?? colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// Un paso de la linea de tiempo: icono en un punto, etiqueta y la fecha legible.
class _FilaTiempo extends StatelessWidget {
  const _FilaTiempo({required this.icono, required this.etiqueta, required this.valor, this.tono, this.conLinea = true});

  final IconData icono;
  final String etiqueta;
  final String? valor;
  final Color? tono;
  final bool conLinea;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hay = valor != null && valor!.isNotEmpty;
    final color = hay ? (tono ?? acentoTinta(context)) : colorScheme.outline;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, size: 15, color: color),
              ),
              if (conLinea)
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: colorScheme.outlineVariant),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: conLinea ? 14 : 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(etiqueta, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ),
                  Text(
                    hay ? valor! : "—",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: hay ? (tono ?? colorScheme.onSurface) : colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dato tecnico: etiqueta a la izquierda y valor a la derecha (mono y copiable si es un identificador).
class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.etiqueta, required this.valor, this.mono = false});

  final String etiqueta;
  final String valor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(etiqueta, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: mono
              ? GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: valor));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$etiqueta copiado.")));
                  },
                  child: Text(
                    valor,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.tech(
                        color: colorScheme.onSurface, fontSize: 11.5, fontWeight: FontWeight.w500, letterSpacing: 0.2),
                  ),
                )
              : Text(
                  valor,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
        ),
      ],
    );
  }
}

class _IconoEstado extends StatefulWidget {
  final Color color;
  final bool animado;
  final ColorScheme colorScheme;

  const _IconoEstado({required this.color, required this.animado, required this.colorScheme});

  @override
  State<_IconoEstado> createState() => _IconoEstadoState();
}

class _IconoEstadoState extends State<_IconoEstado> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    if (widget.animado) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData get _icono {
    if (widget.animado) return Icons.sync;
    if (widget.color == StatusColors.critico) return Icons.error_outline_rounded;
    if (widget.color == StatusColors.exitoso) return Icons.check_circle_outline_rounded;
    if (widget.color == StatusColors.advertencia) return Icons.schedule_rounded;
    return Icons.circle_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = widget.animado ? _controller.value : 0.0;
        final escala = widget.animado ? 0.95 + (t * 0.08) : 1.0;
        return Transform.scale(
          scale: escala,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.color.withValues(alpha: 0.3)),
              boxShadow: widget.animado ? [BoxShadow(color: widget.color.withValues(alpha: 0.35 * t), blurRadius: 10)] : null,
            ),
            child: Icon(_icono, color: widget.color, size: 20),
          ),
        );
      },
    );
  }
}

class _BarraEstado extends StatefulWidget {
  final Color color;
  final bool animada;

  const _BarraEstado({required this.color, required this.animada});

  @override
  State<_BarraEstado> createState() => _BarraEstadoState();
}

class _BarraEstadoState extends State<_BarraEstado> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    if (widget.animada) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animada) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: 1,
          minHeight: 4,
          backgroundColor: widget.color.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation(widget.color),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 4,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _BarraShimmerPainter(color: widget.color, t: _controller.value),
              size: const Size(double.infinity, 4),
            );
          },
        ),
      ),
    );
  }
}

class _BarraShimmerPainter extends CustomPainter {
  final Color color;
  final double t;

  _BarraShimmerPainter({required this.color, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final fondo = Paint()..color = color.withValues(alpha: 0.15);
    canvas.drawRect(Offset.zero & size, fondo);

    final anchoBarra = size.width * 0.35;
    final desplazamiento = (size.width + anchoBarra) * t - anchoBarra;
    final barra = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(desplazamiento, 0, anchoBarra, size.height), barra);
  }

  @override
  bool shouldRepaint(covariant _BarraShimmerPainter oldDelegate) => oldDelegate.t != t;
}
