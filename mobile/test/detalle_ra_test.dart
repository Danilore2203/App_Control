import "package:app_controles/models/ra_archivo.dart";
import "package:app_controles/models/usuario.dart";
import "package:app_controles/services/ra_service.dart";
import "package:app_controles/services/sesion_actual.dart";
import "package:app_controles/theme.dart";
import "package:app_controles/widgets/detalle_ra_sheet.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

const _json = {
  "archivo": "DIM_BOLSILLO_09-11-2026.txt",
  "detalle": {
    "archivo": "DIM_BOLSILLO_09-11-2026.txt",
    "proceso": "JOB_RPL_DIM_BOLSILLO_LOG",
    "estado": "OK",
    "color": "green",
    "fecha_hora": "2026-11-10 05:31:00",
    "tamano": 5120,
    "tamano_ref": 5000,
    "ruta": "/data/raid_uc/params/DIM_BOLSILLO/out/",
  },
  "padres": [
    {
      "proceso": "JOB_RPL_DIM_BOLSILLO_LOG_ALL",
      "tipo": "job_DataStage",
      "fuente": "DATASTAGE",
      "ruta": "OPER_RECUPERADO/JOBS/PARAM_DIM_RA/CONTENEDOR/JOB_RPL_DIM_BOLSILLO_LOG",
      "hora_programada": "02:30:00",
      "hora_log": "2026-11-10 05:30:03",
      "estado": "OK",
      "responsable": "JHONATANT PARDO PAIVA",
    },
    {"proceso": "SIN_TIPO", "estado": "SIN REGISTRO"},
  ],
  "hijos": [
    {"proceso": "dag_bolsillo", "fuente": "AIRFLOW", "estado": "ERROR"},
  ],
};

class _RaFalso extends RaService {
  final pedidos = <String>[];

  @override
  Future<RaDetalle> obtenerDetalle(String archivo) async {
    pedidos.add(archivo);
    return RaDetalle.fromJson(Map<String, dynamic>.from(_json));
  }
}

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);
  tearDown(() => SesionActual.usuario = null);

  test("RaDetalle lee ruta, de qué procesos depende y quién lo usa", () {
    final d = RaDetalle.fromJson(Map<String, dynamic>.from(_json));
    expect(d.archivo?.ruta, "/data/raid_uc/params/DIM_BOLSILLO/out/");
    expect(d.dependeDe.map((p) => p.proceso), ["JOB_RPL_DIM_BOLSILLO_LOG_ALL", "SIN_TIPO"]);
    expect((d.dependeDe.first.fuenteLegible, d.dependeDe.first.lanzable), ("DataStage", true));
    expect(d.dependeDe.last.lanzable, isFalse); // sin fuente no se puede ejecutar
    expect(d.loUsan.single.proceso, "dag_bolsillo");
  });

  testWidgets("el detalle muestra la ruta FTP, las dependencias y ejecuta la elegida", (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SesionActual.usuario = Usuario(id: 1, username: "root", activo: true, esAdmin: true);

    final api = _RaFalso();
    final lanzadas = <RaDependencia>[];
    const archivo = RaArchivo(
      archivo: "DIM_BOLSILLO_09-11-2026.txt",
      proceso: "JOB_RPL_DIM_BOLSILLO_LOG",
      estado: "OK",
      color: "green",
      ruta: "/data/raid_uc/params/DIM_BOLSILLO/out/",
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: DetalleRaSheet(
          archivo: archivo,
          servicio: api,
          lanzar: (d) async => lanzadas.add(d),
        ),
      ),
    ));
    await tester.pump();

    expect(api.pedidos, ["DIM_BOLSILLO_09-11-2026.txt"]);
    expect(find.byKey(const Key("ruta_ftp")), findsOneWidget);
    expect(find.text("/data/raid_uc/params/DIM_BOLSILLO/out/"), findsOneWidget);
    expect(find.text("JOB_RPL_DIM_BOLSILLO_LOG_ALL"), findsOneWidget);
    expect(find.textContaining("Programado 02:30"), findsOneWidget);
    expect(find.text("Responsable: JHONATANT PARDO PAIVA"), findsOneWidget);
    expect(find.text("dag_bolsillo"), findsOneWidget);
    // Solo se ejecuta lo que tiene fuente; «Lo usan» no lleva botón.
    expect(find.byKey(const Key("ejecutar_SIN_TIPO")), findsNothing);
    expect(find.byKey(const Key("ejecutar_dag_bolsillo")), findsNothing);

    final boton = find.byKey(const Key("ejecutar_JOB_RPL_DIM_BOLSILLO_LOG_ALL"));
    await tester.ensureVisible(boton);
    await tester.tap(boton);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, "Ejecutar").last);
    await tester.pump();
    await tester.pump();
    expect(lanzadas.map((d) => (d.proceso, d.fuente, d.ruta)), [
      ("JOB_RPL_DIM_BOLSILLO_LOG_ALL", "DATASTAGE", "OPER_RECUPERADO/JOBS/PARAM_DIM_RA/CONTENEDOR/JOB_RPL_DIM_BOLSILLO_LOG"),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets("sin permisos de administrador no ofrece ejecutar", (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: DetalleRaSheet(
          archivo: const RaArchivo(archivo: "A.txt", proceso: "", estado: "OK", color: "green"),
          servicio: _RaFalso(),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text("JOB_RPL_DIM_BOLSILLO_LOG_ALL"), findsOneWidget);
    expect(find.byKey(const Key("ejecutar_JOB_RPL_DIM_BOLSILLO_LOG_ALL")), findsNothing);
  });
}
