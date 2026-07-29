import "package:flutter/material.dart";

import "../screens/alarma_push_screen.dart";

/// Permite navegar a la pantalla de alarma desde fuera de un widget (p.ej.
/// desde el listener de FirebaseMessaging), usando una key global en el
/// MaterialApp en vez de necesitar un BuildContext de por medio.
class NavegacionService {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static void mostrarAlarma({required String titulo, required String mensaje}) {
    final estado = navigatorKey.currentState;
    if (estado == null) return;
    estado.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AlarmaPushScreen(titulo: titulo, mensaje: mensaje),
      ),
    );
  }
}
