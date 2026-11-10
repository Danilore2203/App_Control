import "package:app_controles/theme.dart";
import "package:app_controles/widgets/boton_actualizar_todos.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

Widget _app(Widget hijo) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: Center(child: hijo)));

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);

  testWidgets("libre se toca; ocupado gira, muestra el avance y no se vuelve a tocar", (tester) async {
    var toques = 0;
    await tester.pumpWidget(_app(BotonActualizarTodos(onPressed: () => toques++)));
    expect(find.text("Actualizar todos"), findsOneWidget);
    await tester.tap(find.byType(BotonActualizarTodos));
    expect(toques, 1);

    await tester.pumpWidget(_app(BotonActualizarTodos(onPressed: () => toques++, ocupado: true)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Actualizando…"), findsOneWidget);
    final giro = tester.widget<RotationTransition>(find.descendant(of: find.byType(BotonActualizarTodos), matching: find.byType(RotationTransition)));
    expect(giro.turns.value, greaterThan(0));
    await tester.tap(find.byType(BotonActualizarTodos));
    expect(toques, 1);

    await tester.pumpWidget(_app(BotonActualizarTodos(onPressed: () => toques++, ocupado: true, completados: 3, total: 12)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("Actualizando 3/12"), findsOneWidget);
    final relleno = tester.widget<FractionallySizedBox>(find.descendant(of: find.byType(BotonActualizarTodos), matching: find.byType(FractionallySizedBox)));
    expect(relleno.widthFactor, closeTo(0.25, 0.001));

    // Termina: vuelve a estar libre y el relleno desaparece.
    await tester.pumpWidget(_app(BotonActualizarTodos(onPressed: () => toques++)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text("Actualizar todos"), findsOneWidget);
    expect(find.descendant(of: find.byType(BotonActualizarTodos), matching: find.byType(FractionallySizedBox)), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
