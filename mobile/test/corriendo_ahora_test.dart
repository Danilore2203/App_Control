import "package:app_controles/models/control.dart";
import "package:app_controles/theme.dart";
import "package:app_controles/widgets/corriendo_ahora.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

Control _c(String nombre, {String color = "blue", String estado = "EN EJECUCION", String fuente = "DATASTAGE", String? inicio}) =>
    Control(
      id: nombre.hashCode,
      tipo: "PROCESO",
      nombre: nombre,
      fuente: fuente,
      estado: estado,
      color: color,
      horaLog: inicio,
      snapshotFecha: DateTime(2026, 11, 11),
      snapshotTs: DateTime(2026, 11, 11, 12, 0),
    );

Widget _app(Widget hijo) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: ListView(children: [hijo])));

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);
  final ahora = DateTime(2026, 11, 11, 12, 0);

  test("Airflow manda la hora en UTC: el tiempo que lleva sale bien igual", () {
    // 15:40 UTC = 11:40 en Bolivia (UTC-4) si el celular está en esa zona;
    // en cualquier zona, nunca queda en el futuro.
    final inicio = CorriendoAhora.inicioDe(_c("dag", fuente: "AIRFLOW", inicio: "2026-11-11 11:40:00"), ahora);
    expect(inicio!.isAfter(ahora), isFalse);
    expect(CorriendoAhora.inicioDe(_c("job", inicio: "2026-11-11 11:40:00"), ahora), DateTime(2026, 11, 11, 11, 40));
    expect(CorriendoAhora.inicioDe(_c("job"), ahora), isNull);
  });

  testWidgets("muestra lo que está corriendo, cuánto lleva, y «Ver en la lista» filtra", (tester) async {
    var verTodos = 0;
    await tester.pumpWidget(_app(CorriendoAhora(
      ahora: () => ahora,
      onVerTodos: () => verTodos++,
      controles: [
        _c("JOB_CARGA_VENTAS", inicio: "2026-11-11 11:40:00"),
        _c("JOB_LARGO", inicio: "2026-11-11 09:30:00"),
        _c("PROCESO_OK", color: "green", estado: "OK", inicio: "2026-11-11 08:00:00"),
        _c("SIN_HORA", fuente: "PENTAHO"),
      ],
    )));
    await tester.pump();

    expect(find.text("Corriendo ahora"), findsOneWidget);
    expect(find.text("3"), findsOneWidget);
    expect(find.text("PROCESO_OK"), findsNothing);
    expect(find.text("20 min"), findsOneWidget);
    expect(find.text("2 h 30 min"), findsOneWidget);
    expect(find.text("en curso"), findsOneWidget); // sin hora de inicio
    expect(find.text("DATASTAGE · desde 11:40"), findsOneWidget);
    // El que lleva más tiempo va primero.
    expect(tester.getTopLeft(find.text("JOB_LARGO")).dy < tester.getTopLeft(find.text("JOB_CARGA_VENTAS")).dy, isTrue);

    await tester.tap(find.byKey(const Key("corriendo_ver_todos")));
    expect(verTodos, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); // corta el reloj y la animación
  });

  testWidgets("sin nada corriendo lo dice en una línea", (tester) async {
    await tester.pumpWidget(_app(CorriendoAhora(
      ahora: () => ahora,
      onVerTodos: () {},
      controles: [_c("PROCESO_OK", color: "green", estado: "OK")],
    )));
    expect(find.text("Nada corriendo en este momento"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
