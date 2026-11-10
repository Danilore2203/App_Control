import "package:app_controles/theme.dart";
import "package:app_controles/widgets/grafica_filas.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

List<PuntoSerie> _serie() => PuntoSerie.deJson({
      "puntos": [
        for (var d = 1; d <= 9; d++) {"fecha": "2026-11-0$d", "cantidad": d == 4 ? 0 : 400000 + d * 1000},
        {"fecha": "2026-11-10", "cantidad": "426020.00"},
      ],
    });

Widget _app(Widget hijo) =>
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: hijo)));

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);

  test("lee la serie como la manda OP_PROD (cantidad puede venir como texto)", () {
    final s = _serie();
    expect(s.length, 10);
    expect((s.last.fecha, s.last.cantidad), (DateTime(2026, 11, 10), 426020));
    expect(PuntoSerie.deJson({"puntos": [{"fecha": "x", "cantidad": 1}]}), isEmpty);
  });

  testWidgets("muestra cifras, días sin carga y el valor del día que se toca", (tester) async {
    await tester.pumpWidget(_app(GraficaFilasPorDia(tabla: "T", cargar: (_) async => _serie())));
    await tester.pump();

    expect(find.text("426.020"), findsOneWidget); // último día
    expect(find.text("Días sin carga"), findsOneWidget);
    expect(find.text("1"), findsOneWidget);
    expect(find.text("Toca la gráfica para ver cada día"), findsOneWidget);

    // Tocar el borde izquierdo elige el primer día.
    final grafica = find.byKey(const Key("grafica_filas"));
    final r = tester.getRect(grafica);
    await tester.tapAt(Offset(r.left + 1, r.center.dy));
    await tester.pump();
    expect(find.text("dom 1 nov · 401.000 filas"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("sin filas registradas lo dice en vez de dibujar una línea en cero", (tester) async {
    await tester.pumpWidget(_app(GraficaFilasPorDia(
      tabla: "bronze.x",
      cargar: (_) async => PuntoSerie.deJson({
        "puntos": [{"fecha": "2026-11-09", "cantidad": 0}, {"fecha": "2026-11-10", "cantidad": 0}],
      }),
    )));
    await tester.pump();
    expect(find.textContaining("No hay filas registradas"), findsOneWidget);
    expect(find.byKey(const Key("grafica_filas")), findsNothing);
  });
}
