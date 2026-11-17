import "package:app_controles/models/control.dart";
import "package:app_controles/theme.dart";
import "package:app_controles/widgets/corriendo_ahora.dart";
import "package:app_controles/widgets/monitor_procesos.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

Control _c(
  String nombre, {
  String fuente = "DATASTAGE",
  String color = "green",
  String estado = "OK",
  String? version,
  String? horaFin,
  String? horaLog,
  String? core,
}) =>
    Control(
      id: nombre.hashCode,
      nombre: nombre,
      fuente: fuente,
      estado: estado,
      color: color,
      version: version,
      horaFin: horaFin,
      horaLog: horaLog,
      core: core,
      snapshotFecha: DateTime(2026, 11, 17),
      snapshotTs: DateTime(2026, 11, 17, 10),
    );

Widget _app(Widget hijo) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: ListView(children: [hijo])));

// Como vienen del catálogo el 17/11: DataStage con versión y hora de fin
// esperada «HH:MM:SS»; Airflow con la fecha completa de su última corrida.
final _ds117 = _c("ETL_DIM_DLMS_LOG_ALL", version: "11.7", horaFin: "10:03:00");
final _ds115 = _c("CONC_115_LOG_ALL", version: "11.5", horaFin: "05:10:00", color: "red", estado: "ERROR");
final _dsSinVersion = _c("EXTRACCION_LOG_ALL", version: "", horaFin: "03:03:00", color: "red", estado: "DEMORADO");
final _pentaho = _c("CHURN_POST_LOG_ALL", fuente: "PENTAHO", horaFin: "11:30:00", color: "gray", estado: "EN TIEMPO", core: "si");
final _airflow = _c("01_silver_alva", fuente: "AIRFLOW", horaLog: "2026-11-17 14:00:00", horaFin: "2026-11-17 14:02:31");
final _airflowCorre = _c("02_silver_corre", fuente: "AIRFLOW", color: "blue", estado: "RUNNING", horaLog: "2026-11-17 13:50:00");
final _otro = _c("ALERTA SESIONES NETEZZA", fuente: "OTRO", horaFin: "08:09:00");
final _todos = [_airflow, _pentaho, _ds117, _otro, _ds115, _dsSinVersion, _airflowCorre];

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);
  final ahora = DateTime(2026, 11, 17, 10, 15);

  test("el Filtro funciona como el de la web, más «Solo Airflow»", () {
    List<String> con(String clave) => _todos.where((c) => cumpleFiltroMotor(clave, c)).map((c) => c.nombre).toList();
    expect(con("ds:ds117"), ["ETL_DIM_DLMS_LOG_ALL"]);
    expect(con("ds:ds115"), ["CONC_115_LOG_ALL"]);
    expect(con("ds:ds150"), isEmpty);
    // «Sin DataStage» es lo que no tiene versión (como en la web: Pentaho, Airflow y DataStage sin versión).
    expect(con("ds:none"), ["01_silver_alva", "CHURN_POST_LOG_ALL", "ALERTA SESIONES NETEZZA", "EXTRACCION_LOG_ALL", "02_silver_corre"]);
    expect(con("tech:datastage"), ["ETL_DIM_DLMS_LOG_ALL", "CONC_115_LOG_ALL", "EXTRACCION_LOG_ALL"]);
    expect(con("tech:pentaho"), ["CHURN_POST_LOG_ALL"]);
    expect(con("tech:airflow"), ["01_silver_alva", "02_silver_corre"]);
    expect(con("tech:other"), ["ALERTA SESIONES NETEZZA"]);
    expect(con("all").length, _todos.length);
    expect(fuenteDelFiltroMotor("ds:ds117"), "DATASTAGE");
    expect(fuenteDelFiltroMotor("tech:airflow"), "AIRFLOW");
    expect(fuenteDelFiltroMotor("ds:none"), isNull);
  });

  test("estado como los contadores de la web: el demorado no cuenta como error", () {
    expect(tonoDe(_ds117), "ok");
    expect(tonoDe(_ds115), "err");
    expect(tonoDe(_dsSinVersion), "delay");
    expect(tonoDe(_pentaho), "pend");
    expect(tonoDe(_airflowCorre), "run");
  });

  test("hora de fin esperada: DataStage y Pentaho sí, Airflow no", () {
    expect(horaEsperada(_ds117), (h: 10, m: 3));
    expect(horaEsperada(_airflow), isNull);
    expect(horaEsperada(_c("SIN_HORA")), isNull);
    expect(horaDeFila(_ds117, ahora), "10:03");
    expect(horaDeFila(_c("SIN_HORA"), ahora), "—");
    // Airflow: la última corrida, en hora del celular (llega en UTC y no puede quedar en el futuro).
    final fila = horaDeFila(_airflow, ahora);
    expect(RegExp(r"^\d{2}:\d{2}$|^\d{2}/\d{2}$").hasMatch(fila), isTrue, reason: fila);
  });

  test("ordena como la web: por hora de fin esperada, Airflow al final", () {
    expect(ordenarComoLaWeb(_todos).map((c) => c.nombre), [
      "EXTRACCION_LOG_ALL", // 03:03
      "CONC_115_LOG_ALL", // 05:10
      "ALERTA SESIONES NETEZZA", // 08:09
      "ETL_DIM_DLMS_LOG_ALL", // 10:03
      "CHURN_POST_LOG_ALL", // 11:30
      "02_silver_corre", // Airflow: 13:50 (empezó)
      "01_silver_alva", // Airflow: 14:02
    ]);
  });

  test("agenda: cuántos cierran en cada hora, por estado; Airflow no entra", () {
    final agenda = calcularAgenda([..._todos, _c("SIN_HORA")]);
    expect(agenda.horas[3], {"delay": 1});
    expect(agenda.horas[10], {"ok": 1});
    expect(agenda.totalDe(11), 1);
    expect(agenda.sinHora, 1);
    expect([for (var h = 0; h < 24; h++) agenda.totalDe(h)].fold(0, (a, b) => a + b), 5);
    expect(proximosCierres(_todos, ahora).map((p) => p.nombre), ["CHURN_POST_LOG_ALL"]);
  });

  test("corre: lo que OP ve en vivo y los DAG de Airflow en ejecución", () {
    final enVivo = enVivoPorNombre(CorriendoEnVivo.fromJson({
      "procesos": [
        {"nombre": "etl_dim_dlms_log_all", "fuente": "DataStage", "desde": "10:00", "hoy": true},
      ],
    }));
    expect(_todos.where((c) => estaCorriendo(c, enVivo)).map((c) => c.nombre), ["ETL_DIM_DLMS_LOG_ALL", "02_silver_corre"]);
  });

  testWidgets("contadores: cuentan por estado y tocar uno filtra (y otra vez lo quita)", (tester) async {
    String? elegido = "x";
    await tester.pumpWidget(_app(ContadoresProcesos(
      controles: _todos,
      corriendo: 2,
      subCorriendo: "+1 fuera del monitor",
      seleccionado: "err",
      onSeleccionar: (v) => elegido = v,
    )));
    expect(find.text("OK"), findsOneWidget);
    expect(find.text("Demorado"), findsOneWidget);
    expect(find.text("En proceso"), findsOneWidget);
    expect(find.text("+1 fuera del monitor"), findsOneWidget);
    // OK: ds117, otro, airflow = 3; Error 1; Demorado 1; Actualizando 1; En proceso 1; Corriendo 2.
    expect(find.descendant(of: find.byKey(const Key("contador_ok")), matching: find.text("3")), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key("contador_corriendo")), matching: find.text("2")), findsOneWidget);
    await tester.tap(find.byKey(const Key("contador_delay")));
    expect(elegido, "delay");
    await tester.tap(find.byKey(const Key("contador_err")));
    expect(elegido, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets("agenda: dice los próximos cierres y tocar una hora la elige", (tester) async {
    int? hora = -1;
    await tester.pumpWidget(_app(AgendaDelDia(controles: _todos, ahora: ahora, onHora: (h) => hora = h)));
    expect(find.text("Agenda del día"), findsOneWidget);
    expect(find.textContaining("Próximos cierres esperados: 11:30 CHURN_POST_LOG_ALL"), findsOneWidget);
    expect(find.textContaining("Airflow no entra"), findsOneWidget);
    await tester.tap(find.byKey(const Key("agenda_hora_10")));
    expect(hora, 10);
    // Una hora vacía no hace nada.
    hora = -1;
    await tester.tap(find.byKey(const Key("agenda_hora_20")));
    expect(hora, -1);
    expect(tester.takeException(), isNull);
  });

  testWidgets("fila: estado, motor, hora de fin y desde cuándo corre", (tester) async {
    await tester.pumpWidget(_app(FilaProceso(
      control: _ds117,
      ahora: ahora,
      enVivo: const {"desde": "10:00", "hoy": true},
      primera: true,
      ultima: true,
    )));
    expect(find.text("ETL_DIM_DLMS_LOG_ALL"), findsOneWidget);
    expect(find.text("DataStage 11.7 · OK"), findsOneWidget);
    expect(find.text("10:00"), findsOneWidget);
    expect(find.text("10:03"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("Corriendo ahora con Todo / DataStage / Pentaho / Airflow, como la web", (tester) async {
    CorriendoEnVivo? avisado;
    await tester.pumpWidget(_app(CorriendoAhora(
      ahora: () => ahora,
      conOrigenes: true,
      onVivo: (v) => avisado = v,
      cargarEnVivo: () async => CorriendoEnVivo.fromJson({
        "procesos": [
          {"nombre": "ETL_DIM_DLMS_LOG_ALL", "fuente": "DataStage", "desde": "10:00", "hoy": true},
          {"nombre": "CHURN_POST_LOG_ALL", "fuente": "Pentaho", "desde": "10:05", "hoy": true},
        ],
      }),
      controles: _todos,
    )));
    await tester.pump();
    await tester.pump();
    expect(avisado?.procesos.length, 2);
    expect(find.text("ETL_DIM_DLMS_LOG_ALL"), findsOneWidget);
    expect(find.text("CHURN_POST_LOG_ALL"), findsOneWidget);
    expect(find.text("02_silver_corre"), findsOneWidget);

    await tester.tap(find.textContaining("Pentaho", findRichText: true).first);
    await tester.pump();
    expect(find.text("CHURN_POST_LOG_ALL"), findsOneWidget);
    expect(find.text("ETL_DIM_DLMS_LOG_ALL"), findsNothing);
    expect(find.text("02_silver_corre"), findsNothing);

    await tester.tap(find.textContaining("Airflow", findRichText: true).first);
    await tester.pump();
    expect(find.text("02_silver_corre"), findsOneWidget);
    expect(find.text("CHURN_POST_LOG_ALL"), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
