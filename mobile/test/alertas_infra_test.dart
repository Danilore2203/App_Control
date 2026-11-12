import "package:app_controles/models/alerta_infra.dart";
import "package:app_controles/theme.dart";
import "package:app_controles/widgets/seccion_alertas_infra.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

Widget _app(Widget hijo) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: ListView(children: [hijo])));

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);

  test("lee activas e historial como los manda el backend (UTC sin zona)", () {
    final d = AlertasInfra.fromJson({
      "activas": [
        {"clave": "netezza.congestion", "abierta": true, "titulo": "Netezza: bloqueo pesado", "mensaje": "La sesión 4711 frena a 3.",
         "abierta_en": "2026-11-12T18:00:00"},
      ],
      "eventos": [
        {"id": 1, "clave": "netezza.congestion", "tipo": "abre", "titulo": "Netezza: bloqueo pesado", "mensaje": "x",
         "creado_en": "2026-11-12T18:00:00"},
      ],
    });
    expect(d.activas.single.abiertaEn!.toUtc(), DateTime.utc(2026, 11, 12, 18));
    expect(d.eventos.single.tipo, "abre");
  });

  testWidgets("una alarma activa se ve en rojo, con cuánto lleva y el historial", (tester) async {
    final abierta = DateTime(2026, 11, 12, 14, 0);
    await tester.pumpWidget(_app(SeccionAlertasInfra(
      ahora: () => DateTime(2026, 11, 12, 14, 25),
      datos: AlertasInfra(
        activas: [
          AlertaInfra(
            clave: "netezza.congestion",
            abierta: true,
            titulo: "Netezza: bloqueo pesado",
            mensaje: "La sesión 4711 (ETL_USER) frena a 3 sesión(es); la más vieja espera 14 min.",
            abiertaEn: abierta,
          ),
        ],
        eventos: [
          EventoInfra(tipo: "abre", titulo: "Netezza: bloqueo pesado", mensaje: "La sesión 4711 frena a 3.", creadoEn: abierta),
        ],
      ),
    )));
    expect(find.text("Netezza: bloqueo pesado"), findsNWidgets(2));
    expect(find.textContaining("hace 25 min"), findsOneWidget);
    expect(find.text("En vivo"), findsOneWidget);
    expect(find.byKey(const Key("ver_infra_netezza.congestion")), findsOneWidget);
    expect(find.text("ÚLTIMOS AVISOS DE INFRAESTRUCTURA"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("sin alarmas dice que Netezza está tranquilo", (tester) async {
    await tester.pumpWidget(_app(const SeccionAlertasInfra(datos: AlertasInfra())));
    expect(find.text("Netezza sin congestión ahora"), findsOneWidget);
    expect(find.text("En vivo"), findsNothing);
  });
}
