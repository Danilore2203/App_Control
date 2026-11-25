import "package:app_controles/services/comandos_service.dart";
import "package:app_controles/services/ejecucion_actual.dart";
import "package:app_controles/services/seguimiento_lanzamiento.dart";
import "package:fake_async/fake_async.dart";
import "package:flutter_test/flutter_test.dart";

/// OP_PROD de mentira: contesta el lanzamiento y luego cada consulta de
/// estado con la siguiente respuesta de la lista; anota lo que se le pidió.
class _OpFalso extends ComandosService {
  _OpFalso(this.lanzamiento, this.estados);

  final Map<String, dynamic> lanzamiento;
  final List<Map<String, dynamic>> estados;
  final pedidos = <(String, Map<String, dynamic>)>[];

  @override
  Future<ResultadoComando> ejecutar(
    String tipo, {
    Map<String, dynamic> payload = const {},
    Duration espera = const Duration(seconds: 90),
    String? titulo,
    bool anunciarFinal = true,
  }) async {
    pedidos.add((tipo, payload));
    final resultado = tipo == "procesos.lanzar" ? lanzamiento : estados.removeAt(0);
    return ResultadoComando(id: pedidos.length, estado: "ok", resultado: resultado);
  }
}

void main() {
  group("Ejecutar ahora en Pentaho", () {
    tearDown(() => EjecucionActual.notifier.value = null);

    test("sigue el job por su id en Pentaho hasta que termina", () {
      fakeAsync((async) {
        final op = _OpFalso(
          {"modo": "pentaho", "lanzado_en": "2026-11-20 14:22:59", "carte_object_id": "abc-123", "secuencia": false},
          [
            {"corriendo": true, "estado_pentaho": "Running"},
            {"corriendo": false, "resultado": "OK", "duracion_seg": 2160, "estado_proceso": "OK"},
          ],
        );
        ejecutarYSeguir(
          tipo: "procesos.lanzar",
          payload: {"nombre": "JOB_ETL_CAMBIOS_DE_SIM_LOG_ALL", "fuente": "PENTAHO"},
          titulo: "Ejecutar JOB_ETL_CAMBIOS_DE_SIM_LOG_ALL",
          seguir: true,
          comandos: op,
        );
        async.elapse(const Duration(seconds: 25));
        final consultas = op.pedidos.where((p) => p.$1 == "procesos.lanzar.estado").toList();
        expect(consultas, hasLength(2));
        expect(consultas.first.$2, {
          "nombre": "JOB_ETL_CAMBIOS_DE_SIM_LOG_ALL",
          "lanzado_en": "2026-11-20 14:22:59",
          "carte_object_id": "abc-123",
          "secuencia": false,
        });
        final fin = EjecucionActual.notifier.value!;
        expect(fin.fase, FaseEjecucion.listo);
        expect(fin.detalle, "Terminó en 36m 00s · el proceso quedó en OK.");
      });
    });

    test("en una secuencia muestra en qué paso va", () {
      fakeAsync((async) {
        final op = _OpFalso(
          {"modo": "pentaho", "lanzado_en": "2026-11-20 14:22:59", "carte_object_id": "", "secuencia": true},
          [
            {"corriendo": true, "estado_pentaho": "Ejecutando TR_PASO_2"},
            {"corriendo": true, "estado_pentaho": "Ejecutando TR_PASO_2"},
          ],
        );
        ejecutarYSeguir(
          tipo: "procesos.lanzar",
          payload: {"nombre": "JOB_SEQ_LOG_ALL", "fuente": "PENTAHO"},
          titulo: "Ejecutar JOB_SEQ_LOG_ALL",
          seguir: true,
          comandos: op,
        );
        async.elapse(const Duration(seconds: 11));
        expect(EjecucionActual.notifier.value!.detalle, endsWith(" · Ejecutando TR_PASO_2"));
        expect(op.pedidos.last.$2["secuencia"], isTrue);
        EjecucionActual.notifier.value = null; // el usuario cierra la barra: se deja de seguir
        async.elapse(const Duration(seconds: 30));
      });
    });

    test("con un OP de antes (sin modo pentaho) se sigue por la tarea, sin id", () {
      fakeAsync((async) {
        final op = _OpFalso(
          {"resultado": "lanzado", "lanzado_en": "2026-11-20 14:22:59"},
          [
            {"corriendo": false, "resultado": "OK", "duracion_seg": 40},
          ],
        );
        ejecutarYSeguir(
          tipo: "procesos.lanzar",
          payload: {"nombre": "JOB_X_LOG_ALL", "fuente": "PENTAHO"},
          titulo: "Ejecutar JOB_X_LOG_ALL",
          seguir: true,
          comandos: op,
        );
        async.elapse(const Duration(seconds: 11));
        expect(op.pedidos.last.$2, {"nombre": "JOB_X_LOG_ALL", "lanzado_en": "2026-11-20 14:22:59"});
        expect(EjecucionActual.notifier.value!.fase, FaseEjecucion.listo);
      });
    });
  });

  group("duracion", () {
    test("segundos, minutos y horas", () {
      expect(SeguimientoLanzamiento.duracion(const Duration(seconds: 48)), "48s");
      expect(SeguimientoLanzamiento.duracion(const Duration(minutes: 3, seconds: 5)), "3m 05s");
      expect(SeguimientoLanzamiento.duracion(const Duration(hours: 1, minutes: 2, seconds: 9)), "1h 02m 09s");
    });

    test("negativa cuenta como cero", () {
      expect(SeguimientoLanzamiento.duracion(const Duration(seconds: -7)), "0s");
    });
  });

  group("resumenFinal", () {
    test("ok con la duracion de OP_PROD y como quedo el proceso", () {
      final (texto, ok) = SeguimientoLanzamiento.resumenFinal(
        {"resultado": "OK", "duracion_seg": 133, "estado_proceso": "OK"},
        const Duration(seconds: 999),
      );
      expect(ok, isTrue);
      expect(texto, "Terminó en 2m 13s · el proceso quedó en OK.");
    });

    test("sin duracion del servidor usa la del telefono", () {
      final (texto, ok) = SeguimientoLanzamiento.resumenFinal({"resultado": "OK"}, const Duration(seconds: 40));
      expect(ok, isTrue);
      expect(texto, "Terminó en 40s.");
    });

    test("error trae el mensaje de OP_PROD", () {
      final (texto, ok) = SeguimientoLanzamiento.resumenFinal(
        {"resultado": "ERROR", "duracion_seg": 40, "mensaje": "Timeout esperando slot Netezza"},
        Duration.zero,
      );
      expect(ok, isFalse);
      expect(texto, "Terminó con ERROR en 40s: Timeout esperando slot Netezza");
    });
  });
}
