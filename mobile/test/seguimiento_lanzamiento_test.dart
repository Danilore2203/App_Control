import "package:app_controles/services/seguimiento_lanzamiento.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
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
