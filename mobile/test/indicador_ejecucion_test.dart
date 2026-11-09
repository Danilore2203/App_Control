import "package:app_controles/services/ejecucion_actual.dart";
import "package:app_controles/theme.dart";
import "package:app_controles/widgets/indicador_ejecucion.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);
  tearDown(EjecucionActual.ocultar);

  Widget app() => MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: Column(children: [Spacer(), IndicadorEjecucion()])),
      );

  testWidgets("sin ejecucion no ocupa lugar", (tester) async {
    await tester.pumpWidget(app());
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets("muestra titulo, detalle y avance de una actualizacion masiva", (tester) async {
    await tester.pumpWidget(app());
    EjecucionActual.mostrar(const EstadoEjecucion(
      titulo: "Actualizar todos los procesos",
      detalle: "Ahora: JOB_X",
      fase: FaseEjecucion.progreso,
      progreso: 0.3,
      completados: 12,
      total: 40,
    ));
    await tester.pumpAndSettle();
    expect(find.text("Actualizar todos los procesos"), findsOneWidget);
    expect(find.text("Ahora: JOB_X"), findsOneWidget);
    expect(find.text("12/40"), findsOneWidget);
    final barra = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(barra.value, 0.3);
  });

  testWidgets("al terminar se puede cerrar con la X", (tester) async {
    await tester.pumpWidget(app());
    EjecucionActual.mostrar(const EstadoEjecucion(
      titulo: "Disparar mi_dag",
      detalle: "Listo.",
      fase: FaseEjecucion.listo,
    ));
    await tester.pumpAndSettle();
    expect(find.text("Listo."), findsOneWidget);
    await tester.tap(find.byTooltip("Ocultar"));
    await tester.pumpAndSettle();
    expect(find.text("Listo."), findsNothing);
  });
}
