import "package:app_controles/models/reporte_ftp.dart";
import "package:app_controles/services/ejecucion_actual.dart";
import "package:app_controles/services/ftp_service.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("ReportesMonitor lee filas, contadores y la cola como los manda OP_PROD", () {
    final m = ReportesMonitor.fromJson({
      "filas": [
        {
          "archivo": "VENTAS.xlsm", "estado": "NO DEPOSITADO", "color": "red", "tipo": "OP",
          "hora_programada": "09:05", "hora_deposito": null, "fecha_modificacion": "2026-11-09 09:01:00",
          "tamanio_mb": "1.25", "descargas_3m": 14, "ruta": "",
        },
        {"archivo": "HIST.xlsx", "estado": "ALMACENADO", "color": "blue", "tipo": ""},
      ],
      "resumen": {"green": 0, "red": 1, "orange": 0, "gray": 0, "blue": 1, "todos": 1},
      "cola": {
        "estado": "corriendo", "mensaje": "Cola iniciada con 2 reporte(s).", "max_abiertos": 2,
        "proxima_hora": "10:00", "conteo": {"abiertos": 1, "pendientes": 1, "terminados": 3, "errores": 0},
        "items": [
          {"id": "a", "archivo": "VENTAS.xlsm", "estado": "abierto", "origen": "cola", "usuario": "darejas (app)"},
          {"id": "b", "archivo": "R2.xlsm", "estado": "pendiente", "hora_programada": "10:00"},
          {"id": "c", "archivo": "R0.xlsm", "estado": "terminado"},
        ],
      },
    });
    final v = m.filas.first;
    expect((v.archivo, v.color, v.horaProgramada, v.horaDeposito, v.tamanioMb, v.descargas3m, v.ruta),
        ("VENTAS.xlsm", "red", "09:05", null, 1.25, 14, null));
    expect((m.todos, m.cuenta("red"), m.cuenta("blue")), (1, 1, 1));
    expect((m.cola.enMarcha, m.cola.sePuedeDetener, m.cola.abiertos, m.cola.pendientes), (true, true, 1, 1));
    expect(m.cola.vivos.map((i) => i.archivo), ["VENTAS.xlsm", "R2.xlsm"]);
  });

  test("sin cola en la respuesta queda inactiva", () {
    final m = ReportesMonitor.fromJson({"filas": [], "resumen": {}});
    expect((m.cola.estado, m.cola.enMarcha, m.cola.finalizada, m.almacenadosTotal), ("inactiva", false, true, null));
  });

  test("almacenados: trae el total aunque solo vengan los mas recientes", () {
    final m = ReportesMonitor.fromJson({
      "filas": [
        {"archivo": "H1.xlsx", "color": "blue", "estado": "ALMACENADO"},
      ],
      "almacenados_total": 14438,
      "resumen": {"blue": 14438, "todos": 196},
    });
    expect((m.filas.length, m.almacenadosTotal, m.todos), (1, 14438, 196));
  });

  test("la barra flotante resume la cola: en curso, pausada y terminada", () {
    ColaReportes cola(String estado, Map<String, int> conteo, {String? proxima}) =>
        ColaReportes(estado: estado, conteo: conteo, maxAbiertos: 2, proximaHora: proxima);

    final enCurso = FtpService.estadoDeCola("t", cola("corriendo", {"abiertos": 0, "pendientes": 3, "terminados": 1}, proxima: "10:00"));
    expect(enCurso.fase, FaseEjecucion.progreso);
    expect(enCurso.detalle, "Abiertos 0/2 · en cola 3 · espera las 10:00");
    expect((enCurso.completados, enCurso.total, enCurso.progreso), (1, 4, 0.25));

    final colgada = FtpService.estadoDeCola("t", cola("pausada", {"colgados": 1, "abiertos": 1}));
    expect(colgada.fase, FaseEjecucion.error);
    expect(colgada.detalle, contains("colgado"));

    final fin = FtpService.estadoDeCola("t", cola("terminada", {"terminados": 4, "errores": 1}));
    expect((fin.fase, fin.detalle), (FaseEjecucion.error, "Cola terminada: 5 de 5 · 1 con error."));
    expect(FtpService.estadoDeCola("t", cola("terminada", {"terminados": 2})).fase, FaseEjecucion.listo);
  });

  test("candidatos: cuantos ya estan en hora", () {
    final c = CandidatosCola.fromJson({
      "elegibles": [
        {"archivo": "A", "tipo": "OP", "ya_toca": true},
        {"archivo": "B", "tipo": "OP", "ya_toca": false, "hora_programada": "18:00"},
      ],
      "omitidos": [
        {"archivo": "C", "tipo": "BI", "motivo": "Tipo BI"},
      ],
    });
    expect((c.elegibles.length, c.yaTocan, c.omitidos.single.motivo), (2, 1, "Tipo BI"));
  });
}
