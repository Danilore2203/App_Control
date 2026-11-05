import "dart:async";

import "package:flutter/widgets.dart";

/// Aviso de que los catálogos cambiaron en el backend.
///
/// Antes cada pantalla preguntaba al servidor cada 60 s aunque no hubiera
/// nada nuevo. Ahora el backend manda un mensaje FCM silencioso
/// ("catalogos_actualizados") apenas OP_PROD le empuja un cambio, y
/// [NotificationService] lo convierte en un evento de este stream: las
/// pantallas se refrescan solo cuando hay algo nuevo, en el mismo minuto.
class ActualizacionesCatalogo {
  ActualizacionesCatalogo._();

  static final ActualizacionesCatalogo instancia = ActualizacionesCatalogo._();

  final _controller = StreamController<void>.broadcast();

  Stream<void> get cambios => _controller.stream;

  void notificar() => _controller.add(null);
}

/// Suscripción de una pantalla al refresco automático: dispara [alRefrescar]
/// cuando llega el aviso del backend y cuando la app vuelve a primer plano
/// (los avisos que llegaron con la app en segundo plano no pasan por el
/// stream, así que al volver se refresca una vez por las dudas).
///
/// Uso: crear en `initState` y llamar a [cancelar] en `dispose`.
class SuscripcionActualizaciones with WidgetsBindingObserver {
  SuscripcionActualizaciones(this._alRefrescar) {
    _suscripcion = ActualizacionesCatalogo.instancia.cambios.listen((_) => _alRefrescar());
    WidgetsBinding.instance.addObserver(this);
  }

  final VoidCallback _alRefrescar;
  late final StreamSubscription<void> _suscripcion;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _alRefrescar();
  }

  void cancelar() {
    _suscripcion.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
