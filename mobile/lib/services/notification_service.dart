import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";

import "api_service.dart";

class NotificationService {
  // FirebaseMessaging.instance solo es valido si Firebase.initializeApp() corrio,
  // lo cual no pasa en web todavia (ver main.dart) - por eso se crea de forma
  // perezosa (no en el constructor) y solo cuando no es web.
  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final ApiService _apiService = ApiService();

  static const AndroidNotificationChannel canalAlarmas = AndroidNotificationChannel(
    "alarmas_criticas",
    "Alarmas de control",
    description: "Alertas criticas cuando falla un proceso monitoreado",
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound("alarma"),
    enableVibration: true,
  );

  Future<void> inicializar() async {
    // Notificaciones push (Firebase) aun no configuradas para web; se omite ahi.
    if (kIsWeb) return;

    final messaging = _messaging ??= FirebaseMessaging.instance;

    // En iOS, `criticalAlert: true` solo tiene efecto real si la app tiene aprobado
    // el entitlement de Apple "Critical Alerts". Mientras tanto, se usa Time-Sensitive
    // (no requiere aprobacion especial) definido del lado del backend en el payload APNs.
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalAlarmas);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings("@mipmap/ic_launcher"),
        iOS: DarwinInitializationSettings(),
      ),
    );

    final token = await messaging.getToken();
    if (token != null) {
      await _apiService.registrarFcmToken(token);
    }
    messaging.onTokenRefresh.listen(_apiService.registrarFcmToken);

    FirebaseMessaging.onMessage.listen(_mostrarNotificacionEnPrimerPlano);
  }

  Future<void> _mostrarNotificacionEnPrimerPlano(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          "alarmas_criticas",
          "Alarmas de control",
          channelDescription: "Alertas criticas cuando falla un proceso monitoreado",
          importance: Importance.max,
          priority: Priority.max,
          sound: RawResourceAndroidNotificationSound("alarma"),
          fullScreenIntent: true,
        ),
        iOS: DarwinNotificationDetails(sound: "alarma.caf", interruptionLevel: InterruptionLevel.timeSensitive),
      ),
    );
  }
}
