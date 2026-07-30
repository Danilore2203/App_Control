import "dart:async";

import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";

/// Abre el detalle de un proceso como bottom sheet (estilo consola/cluster),
/// con datos reales de dataops_catalogo_procesos: sin inventar metricas que
/// no tenemos (CPU/memoria/logs), solo lo que el snapshot realmente trae.
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
    if (control.esDemorado) return StatusColors.advertencia;
    switch (control.color) {
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
    if (diff.inSeconds < 0) return "recien";
    if (diff.inMinutes < 1) return "hace ${diff.inSeconds}s";
    if (diff.inHours < 1) return "hace ${diff.inMinutes}m";
    if (diff.inDays < 1) return "hace ${diff.inHours}h ${diff.inMinutes % 60}m";
    return "hace ${diff.inDays}d";
  }

  String? _sinVacio(String? valor) {
    if (valor == null || valor.trim().isEmpty) return null;
    return valor;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _color(colorScheme);
    final enEjecucion = control.color == "blue";

    final horaProgramada = _sinVacio(control.horaProgramada);
    final horaLog = _sinVacio(control.horaLog);
    final horaFin = _sinVacio(control.horaFin);
    final ruta = _sinVacio(control.ruta);
    final version = _sinVacio(control.version);
    final core = _sinVacio(control.core);

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, -8)),
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
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  control.nombre,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          color: color,
                                          fontWeight: FontWeight.bold),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  border: Border.all(
                                      color: color.withValues(alpha: 0.4)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  control.fuente,
                                  style: AppTextStyles.tech(
                                      color: color, fontSize: 9),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.dns_outlined,
                                  size: 13,
                                  color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  core ?? ruta ?? "dataops_catalogo_procesos",
                                  style: AppTextStyles.tech(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _CasillaStat(
                              titulo: "PROGRAMADO",
                              valor: horaProgramada ?? "—",
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CasillaStat(
                              titulo: "INICIO",
                              valor: horaLog ?? "—",
                              color: colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CasillaStat(
                              titulo: "FIN",
                              valor: horaFin ?? "—",
                              color: control.color == "red" && !control.esDemorado
                                  ? colorScheme.error
                                  : color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "ESTADO DEL PROCESO",
                        style: AppTextStyles.tech(
                            color: colorScheme.onSurfaceVariant, fontSize: 10),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border(left: BorderSide(color: color, width: 3)),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _IconoEstado(
                                    color: color,
                                    animado: enEjecucion,
                                    colorScheme: colorScheme),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        control.estado,
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14),
                                      ),
                                      if (version != null)
                                        Text(
                                          "v$version",
                                          style: TextStyle(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _hace(control.snapshotTs),
                                      style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13),
                                    ),
                                    Text(
                                      "ULTIMA LECTURA",
                                      style: AppTextStyles.tech(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 8),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _BarraEstado(color: color, animada: enEjecucion),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "DETALLE TECNICO",
                        style: AppTextStyles.tech(
                            color: colorScheme.onSurfaceVariant, fontSize: 10),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LineaConsola(
                              texto: "# dataops_catalogo_procesos",
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            _LineaConsola(
                                texto: "fuente: ${control.fuente}",
                                color: colorScheme.onSurfaceVariant),
                            _LineaConsola(
                                texto: "estado: ${control.estado}",
                                color: color),
                            if (ruta != null)
                              _LineaConsola(
                                  texto: "ruta: $ruta",
                                  color: colorScheme.onSurfaceVariant),
                            _LineaConsola(
                              texto:
                                  "snapshot: ${control.snapshotFecha.toIso8601String().split("T").first} ${control.snapshotTs.toIso8601String().substring(11, 19)}",
                              color: colorScheme.primary,
                              conCursor: true,
                            ),
                          ],
                        ),
                      ),
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

class _CasillaStat extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color color;

  const _CasillaStat(
      {required this.titulo, required this.valor, required this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(titulo,
              style: AppTextStyles.tech(
                  color: colorScheme.onSurfaceVariant, fontSize: 8.5)),
          const SizedBox(height: 4),
          Text(
            valor,
            style: AppTextStyles.tech(
                color: color, fontSize: 12, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LineaConsola extends StatefulWidget {
  final String texto;
  final Color color;
  final bool conCursor;

  const _LineaConsola(
      {required this.texto, required this.color, this.conCursor = false});

  @override
  State<_LineaConsola> createState() => _LineaConsolaState();
}

class _LineaConsolaState extends State<_LineaConsola>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Flexible(
            child: Text(
              "> ${widget.texto}",
              style: AppTextStyles.tech(
                  color: widget.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w400),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.conCursor)
            FadeTransition(
              opacity: _controller,
              child: Text(
                " _",
                style: AppTextStyles.tech(
                    color: widget.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconoEstado extends StatefulWidget {
  final Color color;
  final bool animado;
  final ColorScheme colorScheme;

  const _IconoEstado(
      {required this.color, required this.animado, required this.colorScheme});

  @override
  State<_IconoEstado> createState() => _IconoEstadoState();
}

class _IconoEstadoState extends State<_IconoEstado>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    if (widget.animado) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData get _icono {
    if (widget.animado) return Icons.sync;
    if (widget.color == widget.colorScheme.error) return Icons.error_outline;
    return Icons.circle;
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: widget.color.withValues(alpha: 0.3)),
              boxShadow: widget.animado
                  ? [
                      BoxShadow(
                          color: widget.color.withValues(alpha: 0.35 * t),
                          blurRadius: 10)
                    ]
                  : null,
            ),
            child: Icon(_icono, color: widget.color, size: 18),
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

class _BarraEstadoState extends State<_BarraEstado>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
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
              painter: _BarraShimmerPainter(
                  color: widget.color, t: _controller.value),
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
    canvas.drawRect(
        Rect.fromLTWH(desplazamiento, 0, anchoBarra, size.height), barra);
  }

  @override
  bool shouldRepaint(covariant _BarraShimmerPainter oldDelegate) =>
      oldDelegate.t != t;
}
