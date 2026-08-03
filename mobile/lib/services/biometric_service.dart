import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:local_auth/local_auth.dart";

/// Si el usuario ya entro hace poco (p.ej. cerro la app al apagar una
/// alarma con el celular bloqueado -eso cierra la app entera, ver
/// AlarmaPushScreen- y la vuelve a abrir enseguida), pedirle la huella de
/// nuevo es pura friccion sin aportar seguridad real. Recien se vuelve a
/// pedir pasado este tiempo desde el ultimo ingreso exitoso.
const ventanaDeGraciaBiometria = Duration(minutes: 5);

class BiometricService {
  static const _storage = FlutterSecureStorage();
  static const _ultimoIngresoKey = "biometria_ultimo_ingreso_exitoso";

  final _auth = LocalAuthentication();

  Future<bool> disponible() async {
    if (kIsWeb) return false;
    try {
      final soportado = await _auth.isDeviceSupported();
      final puedeChequear = await _auth.canCheckBiometrics;
      return soportado && puedeChequear;
    } catch (_) {
      return false;
    }
  }

  /// Se guarda persistido (no en memoria) porque cerrar la app -por el flujo
  /// de arriba- puede matar el proceso; en memoria se perderia siempre.
  Future<void> registrarIngresoExitoso() => _storage.write(
        key: _ultimoIngresoKey,
        value: DateTime.now().toIso8601String(),
      );

  Future<bool> ingresoRecienteVigente() async {
    final guardado = await _storage.read(key: _ultimoIngresoKey);
    if (guardado == null) return false;
    final ultimo = DateTime.tryParse(guardado);
    if (ultimo == null) return false;
    return DateTime.now().difference(ultimo) < ventanaDeGraciaBiometria;
  }

  Future<bool> autenticar() async {
    try {
      return await _auth.authenticate(
        localizedReason: "Confirma tu identidad para entrar a Controles",
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
