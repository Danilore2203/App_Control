import "package:app_controles/models/netezza_bloqueos.dart";
import "package:app_controles/models/netezza_sesion.dart";
import "package:app_controles/models/postgres_sesion.dart";
import "package:app_controles/theme.dart";
import "package:app_controles/utils/sql_resumen.dart";
import "package:app_controles/widgets/bloqueos_netezza.dart";
import "package:app_controles/widgets/tarjeta_sesion_netezza.dart";
import "package:app_controles/widgets/tarjeta_sesion_postgres.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

Map<String, dynamic> _sesion(int id, {String estado = "corriendo", String cmd = "SELECT 1", int seg = 0, Map<String, dynamic> extra = const {}}) => {
      "SESSION_ID": id,
      "STATUS": "active",
      "USERNAME": "U_ETL",
      "DBNAME": "PR_DWH",
      "IPADDR": "10.49.3.13",
      "CLIENT_OS_USERNAME": "dsadm",
      "CONNTIME": "2026-11-10 08:00:00",
      "COMMAND": cmd,
      "QS_ESTCOST": "8161891",
      "estado": estado,
      "segundos": seg,
      "segundos_medidos": seg,
      ...extra,
    };

final _respuesta = <String, dynamic>{
  "ahora": "2026-11-10 10:30:00",
  "bloqueos": [
    {
      "bloqueadora": _sesion(1, estado: "tx-idle", cmd: "DELETE FROM PR_DWH..FACT_VENTAS WHERE x = 1", seg: 900,
          extra: {"tambien_espera": false, "dag_id": "carga_ventas", "task_id": "borrar"}),
      "esperan": [
        _sesion(2, estado: "esperando", cmd: "TRUNCATE TABLE FACT_VENTAS", seg: 120, extra: {
          "choque": [
            {"tabla": "PR_DWH..FACT_VENTAS", "retiene": "escritura", "pide": "exclusivo"}
          ],
        }),
      ],
    }
  ],
  "esperando_sin_causa": [
    _sesion(3, estado: "esperando", cmd: "UPDATE DIM_CLIENTE SET a = 1", seg: 60, extra: {
      "tablas": [
        {"tabla": "PR_DWH..DIM_CLIENTE", "acceso": "escritura"}
      ],
      "posibles": [_sesion(4, estado: "tx-idle", seg: 3000)],
    }),
  ],
  "tx_abiertas": [
    _sesion(5, estado: "tx-idle", seg: 4000, extra: {
      "tablas": [
        {"tabla": "PR_DWH..T1", "acceso": "lectura"}
      ]
    }),
  ],
  "trabadas": [
    _sesion(6, cmd: "INSERT INTO PR_DWH..NZCC_TT_12_3_STAGE SELECT * FROM EXTERNAL 'x'", extra: {
      "tipo": "sin_avance", "quieta_s": 400, "corre_s": 1500, "pasos": 10, "paso_actual": 4, "segundos": 1500,
    }),
    _sesion(7, cmd: "INSERT INTO PR_DWH..NZCC_TT_12_3_STAGE SELECT * FROM EXTERNAL 'x'", extra: {
      "tipo": "sin_avance", "quieta_s": 350, "corre_s": 1400, "pasos": 10, "paso_actual": 4, "segundos": 1400,
    }),
    _sesion(8, cmd: "SELECT * FROM GRANDE", extra: {"tipo": "en_cola", "segundos": 200}),
    _sesion(9, cmd: "WITH p AS (SELECT 1) SELECT * FROM PR_DWH..HECHOS", extra: {"tipo": "larga", "corre_s": 1004, "pasos": 320, "paso_actual": 176}),
  ],
  "ocupan": [
    _sesion(10, cmd: "SELECT * FROM PESADA", extra: {"corre_s": 700})
  ],
  "resumen": {"bloqueadoras": 1, "esperando": 2, "tx_abiertas": 2, "sin_avance": 2, "en_cola": 1, "cliente": 0, "larga": 1},
  "espera_min_s": 30,
  "umbrales": {"larga_min_s": 600, "sin_avance_s": 300},
};

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);

  group("resumirSql (como la web)", () {
    test("verbo y tabla", () {
      final r = resumirSql("DELETE FROM PR_DWH..FACT_VENTAS WHERE x = 1");
      expect((r.verbo, r.tabla), ("Borra", "PR_DWH..FACT_VENTAS"));
      expect(resumirSql("  select a\n from \"ESQ\".TABLA t").verbo, "Consulta");
      expect(resumirSql("select a from \"ESQ\".TABLA t").tabla, "ESQ.TABLA");
      expect(resumirSql("TRUNCATE TABLE T1").verbo, "Vacía");
      expect(resumirSql(null).verbo, "");
    });

    test("tabla temporal de DataStage y carga externa", () {
      final r = resumirSql("INSERT INTO PR_DWH..NZCC_TT_12_3_STAGE SELECT * FROM EXTERNAL 'x'");
      expect((r.verbo, r.tabla, r.temporal, r.externa), ("Carga", "PR_DWH..STAGE", true, true));
      final d = resumirSql("CREATE EXTERNAL TABLE '/tmp/x' AS SELECT * FROM PR_DWH..VENTAS");
      expect((d.verbo, d.tabla, d.descarga), ("Descarga", "PR_DWH..VENTAS", true));
    });

    test("duraciones y costos cortos", () {
      expect([duracionCorta(45), duracionCorta(600), duracionCorta(3900), duracionCorta(7200)], ["45 s", "10 min", "1 h 5 min", "2 h"]);
      expect([costoCorto(800), costoCorto(80010), costoCorto(8161891), costoCorto(1250000000)], ["800", "80 mil", "8 M", "1,3 mil M"]);
      // 10:29:08 en Bolivia = 14:29:08 UTC, sin importar la zona del celular.
      final ahora = DateTime.utc(2026, 11, 10, 14, 29, 8);
      expect(haceCuanto("2026-11-10 07:29:08 -04", ahora: ahora), "3 h");
      expect(haceCuanto("2026-11-10 07:29:08", ahora: ahora), "3 h"); // sin zona: hora de Bolivia
      expect(haceCuanto("2026-11-10 11:29:08.123 +00", ahora: ahora), "3 h");
      expect(haceCuanto("basura"), isNull);
      expect(extractoSql("WITH p AS (\n SELECT 1 )  SELECT *", largo: 12), "WITH p AS ( …");
    });
  });

  test("BloqueosNetezza lee la respuesta de OP_PROD", () {
    final b = BloqueosNetezza.fromJson(_respuesta);
    expect(b.bloqueos.single.bloqueadora.dagId, "carga_ventas");
    expect(b.bloqueos.single.esperan.single.choque.single.tablaCorta, "FACT_VENTAS");
    expect(b.esperandoSinCausa.single.posibles.single.estado, "tx-idle");
    expect((b.noAvanzan.length, b.enCola.length, b.largas.length), (2, 1, 1));
    expect(b.alertas, 5); // 2 esperando + 2 sin avanzar + 1 en cola
    expect(b.bloqueos.single.bloqueadora.costo, 8161891);
    // Las dos cargas de DataStage con la misma consulta van juntas.
    expect(agruparTrabadas(b.noAvanzan).single.map((s) => s.sessionId), [6, 7]);
    expect(BloqueosNetezza.fromJson(const {"resumen": {"larga": 0}}).todoEnOrden, isTrue);
  });

  testWidgets("la vista de bloqueos dibuja todas las secciones", (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    var abortadas = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      // Va dentro de la lista de Netezza: aca, dentro de una lista cualquiera.
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            BloqueosNetezzaVista(
              datos: BloqueosNetezza.fromJson(_respuesta),
              onAbortar: (s) => abortadas.add(s.sessionId),
              onMatar: (_) {},
            ),
          ],
        ),
      ),
    ));
    expect(find.text("Bloqueos y consultas trabadas"), findsOneWidget);
    expect(find.text("Sesiones que frenan a otras"), findsOneWidget);
    // Las etiquetas llevan el icono dentro del texto: se buscan por contenido.
    expect(find.textContaining("Frena a 1 sesión"), findsOneWidget);
    expect(find.textContaining("Pide acceso exclusivo a FACT_VENTAS"), findsOneWidget);
    expect(find.text("carga_ventas / borrar"), findsOneWidget);
    await tester.tap(find.text("Abortar").first);
    expect(abortadas, [1]);

    await tester.scrollUntilVisible(find.text("No avanzan"), 300);
    expect(find.text("×2 sesiones"), findsOneWidget);
    expect(find.textContaining("Espera filas de DataStage"), findsOneWidget);
    await tester.scrollUntilVisible(find.text("Esperan sin culpable a la vista"), 300);
    await tester.scrollUntilVisible(find.text("Transacciones abiertas sin actividad"), 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets("sin problemas muestra «Todo en orden»", (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListView(children: [BloqueosNetezzaVista(datos: BloqueosNetezza.fromJson(const {"resumen": {}}))]),
      ),
    ));
    expect(find.textContaining("Todo en orden"), findsOneWidget);
    expect(find.text("Cómo se calcula"), findsNothing); // sin problemas, sin la ayuda
  });

  testWidgets("tarjetas de sesiones de Netezza y PostgreSQL", (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ListView(
          children: [
            TarjetaSesionNetezza(
              sesion: NetezzaSesion.fromJson({
                "STATUS": "active", "SESSION_ID": 32592926, "QSC_STATE": "running", "QS_ESTCOST": 2000000,
                "QS_ESTMEM": "3518", "QS_ESTDISK": 5548, "CONNTIME": "2026-11-10 08:28:19", "IPADDR": "10.49.3.13",
                "CLIENT_OS_USERNAME": "dsadm", "USERNAME": "U_ETL", "DBNAME": "PR_DWH", "COMMAND": "INSERT INTO PR_DWH..VENTAS SELECT 1",
              }),
              onAbortar: () {},
              onMatar: () {},
            ),
            TarjetaSesionPostgres(
              sesion: PostgresSesion.fromJson({
                "PID": 2246781, "DATNAME": "dwh_db", "USERNAME": "app_dwh", "APPLICATION_NAME": "PostgreSQL JDBC Driver",
                "CLIENT_ADDR": "10.49.3.13", "BACKEND_START": "2026-11-10 07:29:08 -04", "XACT_START": "2026-11-10 07:29:08 -04",
                "STATE": "active", "WAIT_EVENT": "Lock: relation", "BLOCKING_PIDS": "123, 456", "QUERY_TEXT": "update silver.t set a = 1",
              }),
              bloqueaA: 2,
              onCancelar: () {},
            ),
          ],
        ),
      ),
    ));
    expect(find.text("Sesión 32592926"), findsOneWidget);
    expect(find.text("Corriendo"), findsOneWidget);
    expect(find.text("Costo 2 M"), findsOneWidget);
    expect(find.text("DataStage"), findsOneWidget);
    expect(find.text("PID 2246781"), findsOneWidget);
    expect(find.text("Bloquea a 2 sesiones"), findsOneWidget);
    expect(find.text("Espera a PID 123, 456"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
