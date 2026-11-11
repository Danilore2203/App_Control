import "package:app_controles/models/control.dart";
import "package:app_controles/theme.dart";
import "package:app_controles/widgets/corriendo_ahora.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

Control _c(String nombre, {String color = "blue", String estado = "RUNNING", String fuente = "AIRFLOW", String? inicio}) =>
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

final _vivo = CorriendoEnVivo.fromJson({
  "procesos": [
    {"nombre": "JOB_SEQ_MOD_CLIENTES_LOG_ALL", "fuente": "DataStage", "desde": "11:40", "hoy": true, "pasos": ["JOB_HIJO"]},
    {"nombre": "CARGA_PENTAHO", "fuente": "Pentaho", "desde": "10/11 07:00", "hoy": false},
  ],
  "otros": [
    {"fuente": "DataStage", "job": "JOB_SUELTO", "desde": "11:55", "hoy": true},
  ],
  "fuentes": [
    {"fuente": "DataStage ds117", "ok": true, "n": 2},
    {"fuente": "Pentaho", "ok": false, "error": "Carte no respondió"},
  ],
});

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);
  final ahora = DateTime(2026, 11, 11, 12, 0);

  test("Airflow manda la hora en UTC: el tiempo que lleva sale bien igual", () {
    final inicio = CorriendoAhora.inicioDe(_c("dag", inicio: "2026-11-11 11:40:00"), ahora);
    expect(inicio!.isAfter(ahora), isFalse);
    expect(CorriendoAhora.inicioDe(_c("job", fuente: "DATASTAGE", inicio: "2026-11-11 11:40:00"), ahora),
        DateTime(2026, 11, 11, 11, 40));
  });

  test("lee el «desde» de OP: hora de hoy u otro día", () {
    expect(CorriendoEnVivo.leerDesde("11:40", ahora), DateTime(2026, 11, 11, 11, 40));
    expect(CorriendoEnVivo.leerDesde("10/11 07:00", ahora), DateTime(2026, 11, 10, 7, 0));
    expect(CorriendoEnVivo.leerDesde("22/10", ahora), DateTime(2026, 10, 22));
    expect(CorriendoEnVivo.leerDesde("", ahora), isNull);
  });

  test("junta DataStage/Pentaho en vivo con Airflow del catálogo, sin repetir", () {
    final controles = [
      _c("dag_corriendo", inicio: "2026-11-11 11:50:00"),
      _c("JOB_SEQ_MOD_CLIENTES_LOG_ALL", color: "green", estado: "OK", fuente: "DATASTAGE"),
      _c("OK_QUIETO", color: "green", estado: "OK"),
    ];
    final items = CorriendoAhora.juntar(controles, _vivo, ahora);
    expect(items.map((i) => i.nombre), ["CARGA_PENTAHO", "JOB_SEQ_MOD_CLIENTES_LOG_ALL", "dag_corriendo"]);
    final ds = items[1];
    expect((ds.fuente, ds.control?.nombre), ("DATASTAGE", "JOB_SEQ_MOD_CLIENTES_LOG_ALL"));
    expect(ds.pasos, ["JOB_HIJO"]);
    // Con un filtro de fuente puesto, lo que no está en la lista filtrada no entra.
    expect(CorriendoAhora.juntar(controles, _vivo, ahora, conOtros: false).map((i) => i.nombre),
        ["JOB_SEQ_MOD_CLIENTES_LOG_ALL", "dag_corriendo"]);
  });

  testWidgets("muestra DataStage en vivo, el paso, cuánto lleva y avisos de fuentes", (tester) async {
    await tester.pumpWidget(_app(CorriendoAhora(
      ahora: () => ahora,
      cargarEnVivo: () async => _vivo,
      controles: [
        _c("JOB_SEQ_MOD_CLIENTES_LOG_ALL", color: "green", estado: "OK", fuente: "DATASTAGE"),
        _c("dag_corriendo", inicio: "2026-11-11 11:50:00"),
      ],
    )));
    await tester.pump();
    await tester.pump();

    expect(find.text("Corriendo ahora"), findsOneWidget);
    expect(find.text("3"), findsOneWidget);
    expect(find.text("DATASTAGE · desde 11:40 · paso JOB_HIJO"), findsOneWidget);
    expect(find.text("20 min"), findsOneWidget);
    expect(find.textContaining("No respondió Pentaho"), findsOneWidget);
    expect(find.textContaining("JOB_SUELTO"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("si OP todavía no tiene la función, lo dice y muestra lo del catálogo", (tester) async {
    await tester.pumpWidget(_app(CorriendoAhora(
      ahora: () => ahora,
      cargarEnVivo: () async => throw Exception("El OP del servidor .150 ... hay que reiniciarlo"),
      controles: [_c("dag_corriendo", inicio: "2026-11-11 11:50:00")],
    )));
    await tester.pump();
    await tester.pump();
    expect(find.text("dag_corriendo"), findsOneWidget);
    expect(find.textContaining("hay que reiniciar el OP del .150"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("sin nada corriendo lo dice en una línea", (tester) async {
    await tester.pumpWidget(_app(CorriendoAhora(
      ahora: () => ahora,
      cargarEnVivo: () async => const CorriendoEnVivo(),
      controles: [_c("PROCESO_OK", color: "green", estado: "OK")],
    )));
    await tester.pump();
    expect(find.text("Nada corriendo en este momento"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
