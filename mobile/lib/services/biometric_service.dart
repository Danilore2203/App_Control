import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:local_auth/local_auth.dart";

import "guardia_service.dart";

class BiometricService {
  static const _storage = FlutterSecureStorage();
  static const _ultimoIngresoKey = "biometria_ultimo_ingreso_exitoso";

  /// Vive solo en memoria (a diferencia de _ultimoIngresoKey, que es
  /// persistido a proposito). Si Android mata el proceso -swipe desde
  /// recientes, o el sistema lo mata por memoria- este flag vuelve a false
  /// porque el isolate de Dart entero arranca de cero: no hay forma de que
  /// sobreviva a un proceso muerto. Eso es exactamente lo que se necesita
  /// para distinguir "la app seguia viva en memoria" (aplica la ventana de
  /// gracia) de "esto es un arranque nuevo" (pedir huella siempre, sin
  /// importar la ventana configurada en Ajustes).
  static bool _procesoYaArranco = false;

  final _auth = LocalAuthentication();

  /// true la primera vez que se llama en la vida de este proceso; false en
  /// cualquier llamada posterior mientras el proceso siga vivo.
  bool get esArranqueNuevoDelProceso {
    if (_procesoYaArranco) return false;
    _procesoYaArranco = true;
    return true;
  }

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

  /// Si el usuario ya entro hace poco (p.ej. cerro la app al apagar una
  /// alarma con el celular bloqueado -eso cierra la app entera, ver
  /// AlarmaPushScreen- y la vuelve a abrir enseguida), pedirle la huella de
  /// nuevo es pura friccion sin aportar seguridad real. Recien se vuelve a
  /// pedir pasado este tiempo desde el ultimo ingreso exitoso (configurable
  /// en Ajustes, ver GuardiaService.obtenerVentanaGraciaBiometriaMinutos).
  Future<bool> ingresoRecienteVigente() async {
    final guardado = await _storage.read(key: _ultimoIngresoKey);
    if (guardado == null) return false;
    final ultimo = DateTime.tryParse(guardado);
    if (ultimo == null) return false;
    final minutos = await GuardiaService().obtenerVentanaGraciaBiometriaMinutos();
    return DateTime.now().difference(ultimo) < Duration(minutes: minutos);
  }

  Future<bool> autenticar() async {
    try {
      return await _auth.authenticate(
        localizedReason: "Confirma tu identidad para entrar a Controles",
        // biometricOnly: sin esto, Android puede ofrecer el PIN/patron del
        // celular como alternativa si la huella falla -cualquiera que sepa
        // ese codigo entraria igual, sin haber usado nunca el sensor.
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }
}
