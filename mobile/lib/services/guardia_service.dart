import "package:flutter_secure_storage/flutter_secure_storage.dart";

/// Preferencias de guardia/on-call (armado, horario, tono). Son ajustes
/// propios de este dispositivo, no del backend compartido, asi que se
/// guardan localmente.
class GuardiaService {
  static const _storage = FlutterSecureStorage();
  static const _armadoKey = "guardia_armado";
  static const _horaInicioKey = "guardia_hora_inicio";
  static const _horaFinKey = "guardia_hora_fin";
  static const _tonoUriKey = "guardia_tono_uri";
  static const _notificacionesKey = "notificaciones_habilitadas";

  Future<bool> obtenerArmado() async {
    final valor = await _storage.read(key: _armadoKey);
    return valor == "true";
  }

  Future<void> guardarArmado(bool armado) => _storage.write(
        key: _armadoKey,
        value: armado.toString(),
      );

  // Default 00:00 a 00:00 = guardia las 24hs (ver estaDentroDeHorario): sin
  // esto, activar "armado" sin tocar el horario dejaba la alarma en
  // silencio total fuera de una ventana angosta (antes 00:00-06:00) sin
  // ningun aviso de por que. Armar la guardia debe sonar siempre, salvo que
  // el usuario acote el horario a mano.
  Future<String> obtenerHoraInicio() async =>
      await _storage.read(key: _horaInicioKey) ?? "00:00";

  Future<String> obtenerHoraFin() async =>
      await _storage.read(key: _horaFinKey) ?? "00:00";

  Future<void> guardarHorario(
      {required String inicio, required String fin}) async {
    await _storage.write(key: _horaInicioKey, value: inicio);
    await _storage.write(key: _horaFinKey, value: fin);
  }

  /// URI del tono de alarma elegido del selector nativo de Android. Null =
  /// usar el tono de alarma predeterminado del sistema.
  Future<String?> obtenerTonoUri() => _storage.read(key: _tonoUriKey);

  Future<void> guardarTonoUri(String? uri) => uri == null
      ? _storage.delete(key: _tonoUriKey)
      : _storage.write(key: _tonoUriKey, value: uri);

  /// Por defecto las notificaciones estan habilitadas (no hay valor guardado
  /// todavia la primera vez que se instala la app).
  Future<bool> obtenerNotificacionesHabilitadas() async {
    final valor = await _storage.read(key: _notificacionesKey);
    return valor != "false";
  }

  Future<void> guardarNotificacionesHabilitadas(bool habilitadas) =>
      _storage.write(key: _notificacionesKey, value: habilitadas.toString());

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
