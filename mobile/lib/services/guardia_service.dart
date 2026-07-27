import "package:flutter_secure_storage/flutter_secure_storage.dart";

/// Preferencias de guardia/on-call (armado, horario, tono). Son ajustes
/// propios de este dispositivo, no del backend compartido, asi que se
/// guardan localmente.
class GuardiaService {
  static const _storage = FlutterSecureStorage();
  static const _armadoKey = "guardia_armado";
  static const _horaInicioKey = "guardia_hora_inicio";
  static const _horaFinKey = "guardia_hora_fin";
  static const _tonoKey = "guardia_tono";

  static const tonosDisponibles = [
    "Sirena Nuclear H-9",
    "Alerta de Fallos Críticos",
    "Pulsos de Emergencia",
  ];

  static const archivosPorTono = {
    "Sirena Nuclear H-9": "sounds/alarma_sirena.wav",
    "Alerta de Fallos Críticos": "sounds/alarma_beeps.wav",
    "Pulsos de Emergencia": "sounds/alarma_pulsos.wav",
  };

  Future<bool> obtenerArmado() async {
    final valor = await _storage.read(key: _armadoKey);
    return valor == "true";
  }

  Future<void> guardarArmado(bool armado) => _storage.write(
        key: _armadoKey,
        value: armado.toString(),
      );

  Future<String> obtenerHoraInicio() async =>
      await _storage.read(key: _horaInicioKey) ?? "00:00";

  Future<String> obtenerHoraFin() async =>
      await _storage.read(key: _horaFinKey) ?? "06:00";

  Future<void> guardarHorario(
      {required String inicio, required String fin}) async {
    await _storage.write(key: _horaInicioKey, value: inicio);
    await _storage.write(key: _horaFinKey, value: fin);
  }

  Future<String> obtenerTono() async =>
      await _storage.read(key: _tonoKey) ?? tonosDisponibles.first;

  Future<void> guardarTono(String tono) =>
      _storage.write(key: _tonoKey, value: tono);

  int _minutos(String horaTexto) {
    final partes = horaTexto.split(":");
    return int.parse(partes[0]) * 60 + int.parse(partes[1]);
  }

  /// True si `ahora` cae dentro del rango [inicio, fin). Soporta rangos que
  /// cruzan medianoche (ej. 22:00 a 06:00).
  bool estaDentroDeHorario(DateTime ahora, String inicio, String fin) {
    final minutosAhora = ahora.hour * 60 + ahora.minute;
    final minutosInicio = _minutos(inicio);
    final minutosFin = _minutos(fin);

    if (minutosInicio == minutosFin) return true; // guardia las 24hs
    if (minutosInicio < minutosFin) {
      return minutosAhora >= minutosInicio && minutosAhora < minutosFin;
    }
    return minutosAhora >= minutosInicio || minutosAhora < minutosFin;
  }
}
