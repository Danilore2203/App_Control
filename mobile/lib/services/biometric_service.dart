import "package:flutter/foundation.dart";
import "package:local_auth/local_auth.dart";

class BiometricService {
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
