import "package:app_controles/models/ra_archivo.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("RaMonitor lee filas y contadores como los manda OP_PROD", () {
    final m = RaMonitor.fromJson({
      "filas": [
        {"archivo": "A.txt", "proceso": "P1", "estado": "OK", "color": "green", "fecha_hora": "2026-11-09 08:00:00", "tamano": 120, "tamano_ref": 100},
        {"archivo": "B.txt", "proceso": "", "estado": "ERROR", "color": "red", "fecha_hora": null},
        {"archivo": "C.txt", "proceso": "", "estado": "EN PROCESO", "color": "blue"},
      ],
      "resumen": {"green": 1, "red": 1, "orange": 0, "blue": 1, "gray": 0, "todos": 3},
    });
    expect(m.filas.map((f) => f.estado), ["OK", "ERROR", "EN PROCESO"]);
    expect(m.filas.first.fechaHora, "2026-11-09 08:00:00");
    expect(m.filas[1].fechaHora, isNull);
    expect((m.total, m.cuenta("green"), m.cuenta("red"), m.enProceso), (3, 1, 1, 1));
  });

  test("RaActualizacion resume la sincronizacion y trae el monitor releido", () {
    final r = RaActualizacion.fromJson({
      "resultado": "actualizado",
      "mensaje": "1 de 2 sincronizadas; con error: cfg2.",
      "duracion_seg": 75,
      "insertados": 4,
      "resultados": [
        {"nombre": "cfg1", "ok": true, "insertados": 4, "mensaje": "Insertados 4 registro(s)."},
        {"nombre": "cfg2", "ok": false, "insertados": 0, "mensaje": "FTP timeout"},
      ],
      "resumen": {"green": 2, "red": 0, "orange": 0, "blue": 0, "gray": 0, "todos": 2},
      "filas": [
        {"archivo": "A.txt", "estado": "OK", "color": "green"},
        {"archivo": "B.txt", "estado": "OK", "color": "green"},
      ],
    });
    expect((r.duracionSeg, r.insertados, r.conError), (75, 4, 1));
    expect(r.resultados[1].mensaje, "FTP timeout");
    expect(r.monitor.total, 2);
    expect(r.monitor.filas.length, 2);
  });
}
