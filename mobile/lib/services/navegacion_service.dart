import "package:flutter/material.dart";

import "../screens/alarma_push_screen.dart";
import "../screens/login_screen.dart";

/// Permite navegar desde fuera de un widget (p.ej. desde el listener de
/// FirebaseMessaging, o desde el cliente HTTP cuando la sesion vence),
/// usando una key global en el MaterialApp en vez de necesitar un
/// BuildContext de por medio.
class NavegacionService {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static void mostrarAlarma({
    required int id,
    required String titulo,
    required String mensaje,
    bool esDemorado = false,
    bool esLanzamiento = false,
  }) {
    final estado = navigatorKey.currentState;
    if (estado == null) return;
    estado.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AlarmaPushScreen(
          id: id,
          titulo: titulo,
          mensaje: mensaje,
          esDemorado: esDemorado,
          esLanzamiento: esLanzamiento,
        ),
      ),
    );
  }

  /// Se usa cuando el refresh_token tambien vencio: limpia toda la pila de
  /// pantallas y deja al usuario en el login, en vez de dejarlo viendo
  /// errores genericos en la pantalla en la que estaba.
  static void irALogin() {
    final estado = navigatorKey.currentState;
    if (estado == null) return;
    estado.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}
