import "dart:convert";

import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:permission_handler/permission_handler.dart";

import "../theme.dart";
import "api_service.dart";
import "guardia_foreground_task.dart";
import "guardia_service.dart";
import "navegacion_service.dart";

const String _idCanalAlarmas = "alarmas_criticas_v2";
const String _idCanalNormal = "alertas_normales_v1";

// "_v2"/"_v1": el id de canal esta atado para siempre al sonido/audio
// attributes que tenia la PRIMERA vez que Android lo creo (no se puede
// reconfigurar despues). Cada vez que se cambie el sonido o el tipo de audio
// hay que subir este numero para que se cree un canal nuevo en vez de
// heredar la config vieja de instalaciones anteriores.
const AndroidNotificationChannel canalAlarmas = AndroidNotificationChannel(
  _idCanalAlarmas,
  "Alarmas de control",
  description: "Alertas criticas cuando falla un proceso monitoreado, dentro del horario de guardia",
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound("alarma"),
  enableVibration: true,
  // Trata el sonido como el de un despertador (volumen de alarma, no el de
  // notificaciones) para que suene tambien con el celular en silencio/Do Not
  // Disturb, igual que el reloj despertador del sistema.
  audioAttributesUsage: AudioAttributesUsage.alarm,
);

const AndroidNotificationChannel canalNormal = AndroidNotificationChannel(
  _idCanalNormal,
  "Alertas",
  description: "Avisos de procesos fuera del horario de guardia (o guardia desarmada)",
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// Solo debe sonar como alarma de pantalla completa si la guardia esta
/// armada Y estamos dentro del horario configurado (mismo criterio que ya
/// usa alertas_screen.dart para la alarma en primer plano). Si algo falla al
/// leer la preferencia, se prefiere sonar igual antes que tragarse una
/// alerta real por error.
Future<bool> _debeSonarComoAlarma() async {
  final guardia = GuardiaService();
  const limite = Duration(seconds: 3);
  try {
    final armado = await guardia.obtenerArmado().timeout(limite, onTimeout: () => true);
    if (!armado) return false;
    final inicio =
        await guardia.obtenerHoraInicio().timeout(limite, onTimeout: () => "00:00");
    final fin = await guardia.obtenerHoraFin().timeout(limite, onTimeout: () => "00:00");
    return guardia.estaDentroDeHorario(DateTime.now(), inicio, fin);
  } catch (_) {
    return true;
  }
}

/// Construye y muestra la notificacion A MANO (en vez de dejar que FCM la
/// muestre sola), porque solo asi se le puede pedir pantalla completa
/// (`fullScreenIntent`): eso es lo que hace que Android la lance directo
/// sobre la pantalla de bloqueo, como una alarma real. Funciona igual la
/// llame el listener de primer plano o el manejador de segundo plano.
/// Devuelve `true` si se mostro como alarma de pantalla completa (para que
/// el llamador decida si conviene ademas navegar directo a esa pantalla).
Future<bool> _mostrarNotificacionDeAlarma(RemoteMessage message) async {
  if (message.data["tipo"] != "alerta_critica") return false;

  final titulo = message.data["titulo"] ?? "Alerta crítica";
  final cuerpo = message.data["mensaje"] ?? "Se detectó una falla.";
  final esDemorado = message.data["esDemorado"] == "true";
  final esAlarma = await _debeSonarComoAlarma();

  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(esAlarma ? canalAlarmas : canalNormal);

  await _plugin.show(
    message.hashCode,
    titulo,
    cuerpo,
    NotificationDetails(
      android: esAlarma
          ? AndroidNotificationDetails(
              _idCanalAlarmas,
              "Alarmas de control",
              channelDescription:
                  "Alertas criticas cuando falla un proceso monitoreado, dentro del horario de guardia",
              importance: Importance.max,
              priority: Priority.max,
              sound: const RawResourceAndroidNotificationSound("alarma"),
              audioAttributesUsage: AudioAttributesUsage.alarm,
              category: AndroidNotificationCategory.alarm,
              fullScreenIntent: true,
              color: esDemorado ? StatusColors.advertencia : StatusColors.critico,
              colorized: true,
            )
          : AndroidNotificationDetails(
              _idCanalNormal,
              "Alertas",
              channelDescription: "Avisos de procesos fuera del horario de guardia (o guardia desarmada)",
              importance: Importance.high,
              priority: Priority.high,
            ),
      iOS: DarwinNotificationDetails(
        sound: esAlarma ? "alarma.caf" : null,
        interruptionLevel: esAlarma ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
      ),
    ),
    payload: jsonEncode({
      "titulo": titulo,
      "mensaje": cuerpo,
      "alarma": esAlarma,
      "esDemorado": esDemorado,
    }),
  );

  if (esAlarma) {
    // Para que la notificacion persistente de guardia refleje esta falla
    // apenas ocurre, sin esperar su proximo tick.
    await registrarFallaParaNotificacionPersistente(cuerpo);
  }

  return esAlarma;
}

/// Manejador de mensajes con la app en segundo plano o cerrada del todo.
/// Debe ser una funcion de nivel superior (no un metodo de clase): FCM la
/// corre en un isolate NUEVO Y SEPARADO (motor de Flutter propio), sin nada
/// del estado inicializado en main() -por eso `_plugin` aca es una instancia
/// distinta a la que uso el isolate principal, y hay que inicializarla nueva
/// antes de poder mostrar nada, o `.show()` no hace nada.
@pragma("vm:entry-point")
Future<void> manejarMensajeEnSegundoPlano(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings("@mipmap/ic_launcher"),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await _mostrarNotificacionDeAlarma(message);
}

void _navegarAAlarmaDesdePayload(String? payload) {
  if (payload == null) return;
  try {
    final datos = jsonDecode(payload) as Map<String, dynamic>;
    if (datos["alarma"] != true) return;
    NavegacionService.mostrarAlarma(
      titulo: datos["titulo"] as String? ?? "Alerta crítica",
      mensaje: datos["mensaje"] as String? ?? "",
      esDemorado: datos["esDemorado"] == true,
    );
  } catch (_) {
    // Payload viejo o invalido (p.ej. de una version anterior): se ignora.
  }
}

class NotificationService {
  // FirebaseMessaging.instance solo es valido si Firebase.initializeApp() corrio,
  // lo cual no pasa en web todavia (ver main.dart) - por eso se crea de forma
  // perezosa (no en el constructor) y solo cuando no es web.
  FirebaseMessaging? _messaging;
  final ApiService _apiService = ApiService();

  static bool _localesListas = false;

  /// Deja todo listo para poder mostrar/recibir la alarma incluso ANTES de
  /// hacer login (canal, callback de notificacion tocada, manejador de
  /// segundo plano). Se llama una sola vez, apenas arranca la app.
  Future<void> inicializarTemprano() async {
    if (kIsWeb || _localesListas) return;
    _localesListas = true;

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalAlarmas);

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings("@mipmap/ic_launcher"),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (respuesta) =>
          _navegarAAlarmaDesdePayload(respuesta.payload),
    );

    FirebaseMessaging.onBackgroundMessage(manejarMensajeEnSegundoPlano);

    FirebaseMessaging.onMessage.listen((message) async {
      final esAlarma = await _mostrarNotificacionDeAlarma(message);
      if (esAlarma) {
        // Ya estamos con la app abierta y dentro del horario de guardia: no
        // hace falta esperar a que toquen la notificacion, se muestra la
        // alarma directo.
        NavegacionService.mostrarAlarma(
          titulo: message.data["titulo"] ?? "Alerta crítica",
          mensaje: message.data["mensaje"] ?? "Se detectó una falla.",
          esDemorado: message.data["esDemorado"] == "true",
        );
      }
    });
  }

  /// Si la app fue recien lanzada por el usuario tocando la notificacion (o
  /// por Android al desbloquear gracias al fullScreenIntent), abre la
  /// pantalla de alarma. Se llama despues del primer frame.
  Future<void> revisarLanzamientoPorAlarma() async {
    if (kIsWeb) return;
    final detalles = await _plugin.getNotificationAppLaunchDetails();
    if (detalles?.didNotificationLaunchApp ?? false) {
      _navegarAAlarmaDesdePayload(detalles!.notificationResponse?.payload);
    }
  }

  Future<void> inicializar() async {
    // Notificaciones push (Firebase) aun no configuradas para web; se omite ahi.
    if (kIsWeb) return;

    await inicializarTemprano();

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

    // Sin esto, Android puede matar la app en segundo plano antes de que
    // llegue/suene la alerta push cuando el celular esta bloqueado un rato.
    // Pide el permiso una sola vez (si ya fue otorgado o denegado, no vuelve
    // a molestar).
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    final token = await messaging.getToken();
    if (token != null) {
      await _apiService.registrarFcmToken(token);
    }
    messaging.onTokenRefresh.listen(_apiService.registrarFcmToken);
  }
}
