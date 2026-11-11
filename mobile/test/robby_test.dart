import "package:app_controles/models/usuario.dart";
import "package:app_controles/screens/robby_screen.dart";
import "package:app_controles/services/robby_service.dart";
import "package:app_controles/services/sesion_actual.dart";
import "package:app_controles/theme.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

class _RobbyFalso extends RobbyService {
  final consultas = <String>[];
  final insertados = <String>[];

  @override
  Future<VerificacionRobby> verificar(String proceso) async {
    consultas.add(proceso);
    return VerificacionRobby.fromJson({
      "proceso": proceso,
      "filas": [
        {
          "log": "JOB_RPL_DIM_BOLSILLO_LOG_ALL",
          "nombre_proceso": "JOB_RPL_DIM_BOLSILLO_LOG",
          "estado": "OK",
          "fecha_ejecucion": "2026-11-11",
          "hora": "06:29:43",
          "alfa_proceso_padre": "JOB_RPL_DIM_BOLSILLO_LOG",
        },
      ],
      "robby_filas": 1,
      "alfa_filas": 1,
      "sugerencia": "JOB_RPL_DIM_BOLSILLO_LOG",
      "sql_insert": "INSERT INTO PR_REP_OPERATIVOS.FLUJOS VALUES ( 0,\n'JOB_RPL_DIM_BOLSILLO_LOG',\nNULL, CURRENT_TIMESTAMP, 0 )\n;",
    });
  }

  @override
  Future<String?> insertar(String nombreProceso, {String? titulo}) async {
    insertados.add(nombreProceso);
    return "2026-11-11 11:30:00";
  }
}

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);
  tearDown(() => SesionActual.usuario = null);

  testWidgets("consulta el proceso, sugiere el padre e inserta tras confirmar", (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SesionActual.usuario = Usuario(id: 1, username: "root", activo: true, esAdmin: true);
    final robby = _RobbyFalso();

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: RobbyScreen(procesoInicial: "JOB_RPL_DIM_BOLSILLO_LOG_ALL", servicio: robby),
    ));
    await tester.pump();
    await tester.pump();

    expect(robby.consultas, ["JOB_RPL_DIM_BOLSILLO_LOG_ALL"]);
    expect(find.text("Robby 1 · ALFA 1"), findsOneWidget);
    expect(find.text("Proceso: JOB_RPL_DIM_BOLSILLO_LOG"), findsOneWidget);
    final nombre = tester.widget<TextField>(find.byKey(const Key("robby_nombre_insert")));
    expect(nombre.controller!.text, "JOB_RPL_DIM_BOLSILLO_LOG");
    expect(find.textContaining("INSERT INTO PR_REP_OPERATIVOS.FLUJOS"), findsOneWidget);

    // Un nombre con caracteres raros no se puede insertar.
    await tester.enterText(find.byKey(const Key("robby_nombre_insert")), "X'; DROP");
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key("robby_insertar"))).onPressed, isNull);

    await tester.enterText(find.byKey(const Key("robby_nombre_insert")), "JOB_RPL_DIM_BOLSILLO_LOG");
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key("robby_insertar")));
    await tester.tap(find.byKey(const Key("robby_insertar")));
    await tester.pump();
    expect(find.text("¿Insertar JOB_RPL_DIM_BOLSILLO_LOG en Robby?"), findsOneWidget);
    expect(find.textContaining("ya figura en ALFA"), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, "Insertar"));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(robby.insertados, ["JOB_RPL_DIM_BOLSILLO_LOG"]);
    expect(find.textContaining("Insertado en Robby"), findsOneWidget);
    expect(robby.consultas.length, 2); // vuelve a consultar para ver la fila nueva
    expect(tester.takeException(), isNull);
  });

  testWidgets("sin permisos de administrador no deja usarlo", (tester) async {
    final robby = _RobbyFalso();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: RobbyScreen(procesoInicial: "X", servicio: robby)));
    await tester.pump();
    expect(find.text("Solo administradores"), findsOneWidget);
    expect(robby.consultas, isEmpty);
  });
}
