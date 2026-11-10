import "package:app_controles/models/reporte_ftp.dart";
import "package:app_controles/screens/seleccion_cola_screen.dart";
import "package:app_controles/services/ftp_service.dart";
import "package:app_controles/theme.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

class _FtpFalso extends FtpService {
  @override
  Future<CandidatosCola> candidatosCola() async => CandidatosCola.fromJson({
        "elegibles": [
          {"archivo": "ROBBY_VENTAS.xlsm", "tipo": "ROBBY_REPORT", "color": "red", "hora_programada": "07:30:00", "ya_toca": true},
          {"archivo": "CUBO_24X7.xlsm", "tipo": "24X7", "color": "red", "hora_programada": "15:00:00", "ya_toca": false},
          {"archivo": "OP_DIARIO.xlsm", "tipo": "OP", "color": "gray", "hora_programada": "09:00:00", "ya_toca": true},
        ],
        "omitidos": [
          {"archivo": "BI_X.xlsm", "tipo": "BI", "color": "red", "motivo": "Tipo BI: solo se automatizan ROBBY_REPORT, 24X7, OP"},
        ],
      });
}

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);

  test("CandidatoCola: estado, hora corta y mañana/tarde", () {
    final c = CandidatoCola.fromJson({"archivo": "A", "tipo": "24X7", "color": "gray", "hora_programada": "15:00:00"});
    expect((c.estado, c.horaCorta, c.esDeTarde, c.esDeManana), ("En proceso", "15:00", true, false));
    expect(CandidatoCola.fromJson({"archivo": "B", "tipo": "OP"}).estado, "No depositado");
  });

  testWidgets("elige por tipo (Robby y 24x7) y devuelve solo los marcados", (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    List<String>? elegidos;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                elegidos = await Navigator.of(context).push<List<String>>(
                  MaterialPageRoute(builder: (_) => SeleccionColaScreen(servicio: _FtpFalso())),
                );
              },
              child: const Text("abrir"),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("abrir"));
    await tester.pumpAndSettle();

    expect(find.text("3 de 3 marcados"), findsOneWidget);
    expect(find.text("espera 15:00"), findsOneWidget);
    expect(find.textContaining("Lanzar 3 reporte(s) · 1 esperan su hora"), findsOneWidget);

    // Fuera los OP: quedan ROBBY_REPORT y 24X7.
    await tester.tap(find.byKey(const Key("tipo_OP")));
    await tester.pump();
    expect(find.text("OP_DIARIO.xlsm"), findsNothing);
    expect(find.text("2 de 2 marcados"), findsOneWidget);

    // Desmarcar el 24X7 tocando la fila.
    await tester.tap(find.text("CUBO_24X7.xlsm"));
    await tester.pump();
    expect(find.text("1 de 2 marcados"), findsOneWidget);

    await tester.scrollUntilVisible(find.text("No entran (1)"), 200);
    expect(find.text("No entran (1)"), findsOneWidget);

    await tester.tap(find.byKey(const Key("lanzar_marcados")));
    await tester.pumpAndSettle();
    expect(elegidos, ["ROBBY_VENTAS.xlsm"]);
    expect(tester.takeException(), isNull);
  });

  testWidgets("«Todos» desmarca y vuelve a marcar lo visible", (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: SeleccionColaScreen(servicio: _FtpFalso())));
    await tester.pump();
    await tester.tap(find.byKey(const Key("marcar_todos")));
    await tester.pump();
    expect(find.text("0 de 3 marcados"), findsOneWidget);
    expect(find.text("Marca al menos un reporte"), findsOneWidget);
    await tester.tap(find.byKey(const Key("marcar_todos")));
    await tester.pump();
    expect(find.text("3 de 3 marcados"), findsOneWidget);
  });
}
