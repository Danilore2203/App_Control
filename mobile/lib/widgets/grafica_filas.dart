import "dart:math" as math;

import "package:flutter/material.dart";

import "../services/comandos_service.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "titulo_seccion.dart";

/// Un dia de la serie «Filas por día» de una tabla.
class PuntoSerie {
  final DateTime fecha;
  final num cantidad;

  const PuntoSerie(this.fecha, this.cantidad);

  static List<PuntoSerie> deJson(Map<String, dynamic> json) => ((json["puntos"] as List?) ?? const [])
      .whereType<Map>()
      .map((p) {
        final fecha = DateTime.tryParse((p["fecha"] ?? "").toString());
        return fecha == null ? null : PuntoSerie(fecha, leerNumero(p["cantidad"]) ?? 0);
      })
      .whereType<PuntoSerie>()
      .toList();
}

/// «Filas por día» como en el detalle de Tablas de la web: lo que cargó la
/// tabla cada día de los últimos 40 (los días en 0 van en rojo). Se toca o
/// se arrastra sobre la gráfica para ver el valor de cada día.
class GraficaFilasPorDia extends StatefulWidget {
  const GraficaFilasPorDia({super.key, required this.tabla, this.cargar});

  final String tabla;

  /// Para las pruebas; normalmente pide `tablas.serie` a OP_PROD.
  final Future<List<PuntoSerie>> Function(String tabla)? cargar;

  @override
  State<GraficaFilasPorDia> createState() => _GraficaFilasPorDiaState();
}

class _GraficaFilasPorDiaState extends State<GraficaFilasPorDia> {
  late Future<List<PuntoSerie>> _serie = _pedir();
  int? _elegido;

  Future<List<PuntoSerie>> _pedir() {
    final cargar = widget.cargar;
    if (cargar != null) return cargar(widget.tabla);
    return ComandosService()
        .ejecutar("tablas.serie", payload: {"tabla": widget.tabla})
        .then((r) => PuntoSerie.deJson(r.resultado));
  }

  void _elegir(Offset local, double ancho, int n) {
    if (n == 0 || ancho <= 0) return;
    final i = ((local.dx / ancho) * (n - 1)).round().clamp(0, n - 1);
    if (i != _elegido) setState(() => _elegido = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return FutureBuilder<List<PuntoSerie>>(
      future: _serie,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (snap.hasError) {
          final e = snap.error;
          return _Aviso(
            texto: "No se pudo cargar la gráfica: ${e is ComandoFallidoException ? e.mensaje : e}",
            onReintentar: () => setState(() => _serie = _pedir()),
          );
        }
        final puntos = snap.data ?? const <PuntoSerie>[];
        if (puntos.isEmpty || puntos.every((p) => p.cantidad == 0)) {
          return const _Aviso(texto: "No hay filas registradas para esta tabla en los últimos 40 días.");
        }
        final ultimo = puntos.last;
        final ultimos7 = puntos.length >= 7 ? puntos.sublist(puntos.length - 7) : puntos;
        final promedio = ultimos7.fold<num>(0, (a, p) => a + p.cantidad) / ultimos7.length;
        final sinCarga = puntos.where((p) => p.cantidad == 0).length;
        final elegido = _elegido == null ? null : puntos[_elegido!];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Cifra("Último día", formatearMiles(ultimo.cantidad.round())),
                _Cifra("Promedio 7 días", formatearMiles(promedio.round())),
                _Cifra("Días sin carga", "$sinCarga", tono: sinCarga > 0 ? StatusColors.critico : null),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 22,
              child: Text(
                elegido == null
                    ? "Toca la gráfica para ver cada día"
                    : "${_dia(elegido.fecha)} · ${formatearMiles(elegido.cantidad.round())} filas",
                key: const Key("grafica_valor"),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: elegido == null ? colorScheme.outline : colorScheme.onSurface,
                  fontWeight: elegido == null ? FontWeight.w500 : FontWeight.w800,
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _elegir(d.localPosition, c.maxWidth, puntos.length),
                onHorizontalDragUpdate: (d) => _elegir(d.localPosition, c.maxWidth, puntos.length),
                child: CustomPaint(
                  key: const Key("grafica_filas"),
                  size: Size(c.maxWidth, 150),
                  painter: _PintorSerie(
                    puntos: puntos,
                    promedio: promedio.toDouble(),
                    elegido: _elegido,
                    linea: acentoTinta(context),
                    cero: StatusColors.critico,
                    guia: colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(_corta(puntos.first.fecha), style: _ejes(theme, colorScheme)),
                const Spacer(),
                Text(_corta(puntos[puntos.length ~/ 2].fecha), style: _ejes(theme, colorScheme)),
                const Spacer(),
                Text(_corta(ultimo.fecha), style: _ejes(theme, colorScheme)),
              ],
            ),
          ],
        );
      },
    );
  }

  static TextStyle? _ejes(ThemeData theme, ColorScheme cs) => theme.textTheme.labelSmall?.copyWith(color: cs.outline);

  static const _meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
  static const _diasSemana = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"];

  static String _corta(DateTime f) => "${f.day} ${_meses[f.month - 1]}";
  static String _dia(DateTime f) => "${_diasSemana[f.weekday - 1]} ${_corta(f)}";
}

class _PintorSerie extends CustomPainter {
  _PintorSerie({
    required this.puntos,
    required this.promedio,
    required this.elegido,
    required this.linea,
    required this.cero,
    required this.guia,
  });

  final List<PuntoSerie> puntos;
  final double promedio;
  final int? elegido;
  final Color linea;
  final Color cero;
  final Color guia;

  @override
  void paint(Canvas canvas, Size size) {
    if (puntos.isEmpty) return;
    final maximo = math.max(puntos.map((p) => p.cantidad.toDouble()).reduce(math.max), 1.0);
    const arriba = 8.0;
    final alto = size.height - arriba - 4;
    double x(int i) => puntos.length == 1 ? size.width / 2 : size.width * i / (puntos.length - 1);
    double y(num v) => arriba + alto * (1 - v.toDouble() / maximo);

    // Guias horizontales (0, mitad, maximo).
    final pGuia = Paint()
      ..color = guia.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final yy = arriba + alto * f;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), pGuia);
    }

    final camino = Path()..moveTo(x(0), y(puntos.first.cantidad));
    for (var i = 1; i < puntos.length; i++) {
      camino.lineTo(x(i), y(puntos[i].cantidad));
    }
    final area = Path.from(camino)
      ..lineTo(x(puntos.length - 1), arriba + alto)
      ..lineTo(x(0), arriba + alto)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [linea.withValues(alpha: 0.30), linea.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, arriba, size.width, alto)),
    );
    canvas.drawPath(
      camino,
      Paint()
        ..color = linea
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Promedio de los ultimos 7 dias, punteado.
    final yProm = y(promedio);
    final pProm = Paint()
      ..color = linea.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;
    for (var xx = 0.0; xx < size.width; xx += 8) {
      canvas.drawLine(Offset(xx, yProm), Offset(math.min(xx + 4, size.width), yProm), pProm);
    }

    // Dias sin carga en rojo.
    for (var i = 0; i < puntos.length; i++) {
      if (puntos[i].cantidad == 0) {
        canvas.drawCircle(Offset(x(i), y(0)), 3.2, Paint()..color = cero);
      }
    }

    final e = elegido;
    if (e != null && e >= 0 && e < puntos.length) {
      canvas.drawLine(
        Offset(x(e), arriba),
        Offset(x(e), arriba + alto),
        Paint()
          ..color = linea.withValues(alpha: 0.7)
          ..strokeWidth = 1,
      );
      final centro = Offset(x(e), y(puntos[e].cantidad));
      canvas.drawCircle(centro, 5.5, Paint()..color = puntos[e].cantidad == 0 ? cero : linea);
      canvas.drawCircle(centro, 2.5, Paint()..color = Colors.black);
    }
  }

  @override
  bool shouldRepaint(_PintorSerie old) =>
      old.puntos != puntos || old.elegido != elegido || old.linea != linea || old.promedio != promedio;
}

class _Cifra extends StatelessWidget {
  const _Cifra(this.etiqueta, this.valor, {this.tono});

  final String etiqueta;
  final String valor;
  final Color? tono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiqueta, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        Text(
          valor,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: tono),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, this.onReintentar});

  final String texto;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.show_chart_rounded, size: 18, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        if (onReintentar != null)
          IconButton(onPressed: onReintentar, icon: const Icon(Icons.refresh_rounded, size: 18), tooltip: "Reintentar"),
      ],
    );
  }
}
