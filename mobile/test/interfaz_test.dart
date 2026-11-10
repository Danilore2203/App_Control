import "package:app_controles/models/control.dart";
import "package:app_controles/screens/alertas_screen.dart";
import "package:app_controles/theme.dart";
import "package:app_controles/utils/formato.dart";
import "package:app_controles/widgets/monitoreo_por_fuente.dart";
import "package:app_controles/widgets/tarjeta_proceso.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

Control _control(String nombre, {String color = "green", String estado = "OK", String fuente = "AIRFLOW",
        String? fin, String? inicio, String? prog, String? core, String tipo = "PROCESO", int? cantidad, String? layer}) =>
    Control(
      id: nombre.hashCode,
      tipo: tipo,
      nombre: nombre,
      fuente: fuente,
      estado: estado,
      color: color,
      horaFin: fin,
      horaLog: inicio,
      horaProgramada: prog,
      core: core,
      cantidad: cantidad,
      layer: layer,
      snapshotFecha: DateTime(2026, 11, 10),
      snapshotTs: DateTime(2026, 11, 10, 10, 29),
    );

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);

  group("fechas legibles", () {
    final ahora = DateTime(2026, 11, 10, 11, 20);

    test("fechaAmigable y diaAmigable", () {
      expect(fechaAmigable(DateTime(2026, 11, 10, 14, 0, 5), ahora: ahora), "Hoy 14:00");
      expect(fechaAmigable(DateTime(2026, 11, 9, 15, 15), ahora: ahora), "Ayer 15:15");
      expect(fechaAmigable(DateTime(2026, 7, 2, 19, 26), ahora: ahora), "2 jul · 19:26");
      expect(fechaAmigable(DateTime(2024, 10, 24, 13, 24), ahora: ahora), "24 oct 2024");
      expect(diaAmigable(DateTime(2026, 11, 9, 23, 59), ahora: ahora), "Ayer");
    });

    test("fecha del catalogo sin cambiar de zona, solo hora y duracion", () {
      expect(fechaCatalogo("2026-11-10 14:00:05", ahora: ahora), "Hoy 14:00");
      expect(fechaCatalogo("08:09:00", ahora: ahora), "08:09");
      expect(fechaCatalogo("", ahora: ahora), isNull);
      expect(duracionEntre("2026-11-10 13:55:00", "2026-11-10 14:00:05"), "5 min");
      expect(duracionEntre("2026-11-10 14:00:05", "2026-11-10 13:00:00"), isNull);
      expect(duracionEntre(null, "2026-11-10 13:00:00"), isNull);
    });

    test("fechaUtc: lo que el backend guarda en UTC sin zona pasa a la hora del celular", () {
      final f = fechaUtc("2026-11-10T13:06:42.696836");
      expect(f.isUtc, isFalse);
      expect(f.toUtc(), DateTime.utc(2026, 11, 10, 13, 6, 42, 696, 836));
      // Con zona se respeta.
      expect(fechaUtc("2026-11-10T09:06:00-04:00").toUtc(), DateTime.utc(2026, 11, 10, 13, 6));
    });
  });

  test("las tablas core se leen del catalogo como los procesos core", () {
    Map<String, dynamic> json(String nombre, String? core) => {
          "id": 1, "nombre": nombre, "fuente": "QA_CONTROL", "estado": "OK", "color": "green", "cantidad": 10,
          "snapshot_fecha": "2026-11-10", "snapshot_ts": "2026-11-10T10:00:00", "core": core,
        };
    expect(esCore(Control.fromTablaJson(json("DW.DIM_PERSONA", "SI"))), isTrue);
    expect(esCore(Control.fromTablaJson(json("DW.OTRA", null))), isFalse);
  });

  group("AlertaLeida", () {
    test("[FUENTE] NOMBRE: ESTADO", () {
      final a = AlertaLeida.de("[DATASTAGE] RUN_SCHURN_PRE_LOG_ALL: DEMORADO");
      expect((a.fuente, a.titulo, a.estado), ("DATASTAGE", "RUN_SCHURN_PRE_LOG_ALL", "DEMORADO"));
      expect(a.tono.$1, "Demorado");
    });

    test("incoherencia: el proceso es el titulo y el resto el detalle", () {
      final a = AlertaLeida.de(
          "Proceso JOB_CARGA_X en incoherencia a las 09:01: finalizó OK pero la tabla bronze.t quedó en estado ERROR (posible fallo silencioso)");
      expect((a.titulo, a.estado), ("JOB_CARGA_X", "INCOHERENCIA"));
      expect(a.detalle, "Finalizó OK pero la tabla bronze.t quedó en estado ERROR (posible fallo silencioso)");
      expect(a.tono.$2, StatusColors.critico);
    });

    test("un mensaje libre queda tal cual", () {
      final a = AlertaLeida.de("Algo raro pasó");
      expect((a.titulo, a.estado, a.tono.$1), ("Algo raro pasó", null, "Aviso"));
    });
  });

  testWidgets("la fila del proceso dice el estado en palabras y una sola vez", (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ListView(
          children: [
            TarjetaProceso(control: _control("01_silver_alva", color: "red", estado: "ERROR", fin: "2026-07-28 15:21:08", core: "SI")),
            TarjetaProceso(control: _control("CARGA_DEMORADA", color: "red", estado: "DEMORADO", fuente: "DATASTAGE", prog: "08:00:00")),
            TarjetaProceso(
                control: _control("bronze.t", tipo: "TABLA", fuente: "QA_CONTROL", cantidad: 1234567, layer: "silver")),
          ],
        ),
      ),
    ));
    expect(find.textContaining("Falló 28 jul · 15:21"), findsOneWidget);
    expect(find.text("CORE"), findsOneWidget);
    expect(find.textContaining("Demorado · prog. 08:00"), findsOneWidget);
    expect(find.textContaining("1.234.567 reg."), findsOneWidget);
    expect(find.text("ERROR"), findsNothing); // ya no repite el estado en mayusculas
    expect(tester.takeException(), isNull);
  });

  testWidgets("las tarjetas por fuente cuentan errores y demorados, primero las que fallan", (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: MonitoreoPorFuente(controles: [
          _control("a", fuente: "DATASTAGE"),
          _control("b", fuente: "DATASTAGE", color: "red", estado: "DEMORADO"),
          _control("c", fuente: "AIRFLOW", color: "red", estado: "ERROR"),
          _control("d", fuente: "AIRFLOW"),
          _control("e", fuente: "AIRFLOW", core: "SI"),
        ]),
      ),
    ));
    expect(find.text("1 con error"), findsOneWidget);
    expect(find.text("1 demorado"), findsOneWidget);
    expect(find.text("de 3 procesos"), findsOneWidget);
    expect(find.text("de 1 crítico"), findsOneWidget);
    final airflow = tester.getTopLeft(find.text("AIRFLOW")).dx;
    final datastage = tester.getTopLeft(find.text("DATASTAGE")).dx;
    expect(airflow < datastage, isTrue);
    // La barra de mezcla se ve: sus segmentos tienen alto.
    final segmentos = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).toList();
    expect(segmentos, isNotEmpty);
    for (final e in find.byType(ColoredBox).evaluate()) {
      expect((e.renderObject as RenderBox).size.height, greaterThan(0));
    }
    expect(tester.takeException(), isNull);
  });
}
