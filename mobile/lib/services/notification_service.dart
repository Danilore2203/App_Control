import "dart:convert";

import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:permission_handler/permission_handler.dart";

import "../theme.dart";
import "api_service.dart";
import "guardia_foreground_task.dart";
import "guardia_service.dart";
import "navegacion_service.dart";

const String _idCanalAlarmas = "alarmas_criticas_v2";
const String _idCanalAlarmasFallback = "alarmas_criticas_fallback_v1";
const String _idCanalNormal = "alertas_normales_v1";

// URI del sonido de alarma predeterminado del sistema (el mismo que usa el
// reloj despertador de Android). Siempre existe en el dispositivo, a
// diferencia del tono propio empaquetado como recurso raw.
const String _uriSonidoAlarmaSistema = "content://settings/system/alarm_alert";

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

const AndroidNotificationChannel canalAlarmasFallback = AndroidNotificationChannel(
  _idCanalAlarmasFallback,
  "Alarmas de control (sonido del sistema)",
  description:
      "Igual que Alarmas de control, pero con el sonido de alarma predeterminado del sistema "
      "(se usa si el tono propio no se pudo cargar)",
  importance: Importance.max,
  playSound: true,
  sound: UriAndroidNotificationSound(_uriSonidoAlarmaSistema),
  enableVibration: true,
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

/// Ultimo recurso: si CUALQUIER cosa del camino normal de la alarma explota
/// (canal roto, sonido roto, lo que sea), esto muestra una notificacion
/// minima -sin sonido custom, sin fullScreenIntent, nada que pueda fallar
/// a su vez- con el motivo real del error. Sin esto, una excepcion en un
/// isolate de background moria en silencio total: no crasheaba nada
/// visible, no dejaba log en ningun lado que el usuario pueda ver, y la
/// alarma real simplemente no aparecia sin ninguna pista de por que.
Future<void> _mostrarErrorDiagnostico(String detalle) async {
  try {
    await _plugin.show(
      999999,
      "No se pudo mostrar la alarma",
      detalle,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          "diagnostico_errores_v1",
          "Errores de la app",
          channelDescription: "Avisa si la alarma no se pudo mostrar por algun error",
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  } catch (_) {
    // Si hasta esto falla, ya no hay nada mas que la app pueda hacer del
    // lado de Dart: el problema esta en el sistema, no en este codigo.
  }
}

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

/// Muestra la alarma de pantalla completa A MANO (en vez de dejar que FCM la
/// muestre sola), porque solo asi se le puede pedir pantalla completa
/// (`fullScreenIntent`): eso es lo que hace que Android la lance directo
/// sobre la pantalla de bloqueo, como una alarma real. Publica (no privada)
/// porque tambien la usa `guardia_foreground_task.dart` como via de
/// respaldo: si Android mata la app y nunca llega a procesar el push (mas
/// comun de lo que deberia en Xiaomi/Samsung/Huawei sin autoarranque), el
/// Foreground Service -que tiene mucha mas proteccion contra esos mismos
/// bloqueos- puede disparar esta misma alarma el mismo, sin depender de FCM.
NotificationDetails _detallesAlarma(bool esDemorado, {required bool conSonidoPropio}) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      conSonidoPropio ? _idCanalAlarmas : _idCanalAlarmasFallback,
      conSonidoPropio ? "Alarmas de control" : "Alarmas de control (sonido del sistema)",
      channelDescription:
          "Alertas criticas cuando falla un proceso monitoreado, dentro del horario de guardia",
      importance: Importance.max,
      priority: Priority.max,
      sound: conSonidoPropio
          ? const RawResourceAndroidNotificationSound("alarma")
          : const UriAndroidNotificationSound(_uriSonidoAlarmaSistema),
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      color: esDemorado ? StatusColors.advertencia : StatusColors.critico,
      colorized: true,
    ),
    iOS: DarwinNotificationDetails(
      sound: conSonidoPropio ? "alarma.caf" : null,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );
}

Future<void> mostrarAlarmaLocal({
  required int id,
  required String titulo,
  required String mensaje,
  required bool esDemorado,
}) async {
  final payload = jsonEncode({
    "titulo": titulo,
    "mensaje": mensaje,
    "alarma": true,
    "esDemorado": esDemorado,
  });

  try {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalAlarmas);
    await _plugin.show(
      id,
      titulo,
      mensaje,
      _detallesAlarma(esDemorado, conSonidoPropio: true),
      payload: payload,
    );
  } on PlatformException catch (e) {
    if (e.code != "invalid_sound") rethrow;
    // El tono propio no se pudo resolver (instalacion vieja sin el recurso,
    // resource shrinking, etc.). Se cae al sonido de alarma predeterminado
    // del sistema -que siempre existe en el dispositivo- en un canal
    // distinto: la alarma tiene que sonar si o si, aunque no sea con el tono
    // propio.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canalAlarmasFallback);
    await _plugin.show(
      id,
      titulo,
      mensaje,
      _detallesAlarma(esDemorado, conSonidoPropio: false),
      payload: payload,
    );
  }

  // Para que la notificacion persistente de guardia refleje esta falla
  // apenas ocurre, sin esperar su proximo tick.
  await registrarFallaParaNotificacionPersistente(mensaje);
}

/// Muestra la notificacion que llega por push A MANO. Devuelve `true` si se
/// mostro como alarma de pantalla completa (para que el llamador decida si
/// conviene ademas navegar directo a esa pantalla). Funciona igual la llame
/// el listener de primer plano o el manejador de segundo plano.
Future<bool> _mostrarNotificacionDeAlarma(RemoteMessage message) async {
  if (message.data["tipo"] != "alerta_critica") return false;

  final titulo = message.data["titulo"] ?? "Alerta crítica";
  final cuerpo = message.data["mensaje"] ?? "Se detectó una falla.";
  final esDemorado = message.data["esDemorado"] == "true";
  final esAlarma = await _debeSonarComoAlarma();

  if (esAlarma) {
    await mostrarAlarmaLocal(
      id: message.hashCode,
      titulo: titulo,
      mensaje: cuerpo,
      esDemorado: esDemorado,
    );
    return true;
  }

  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(canalNormal);

  await _plugin.show(
    message.hashCode,
    titulo,
    cuerpo,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _idCanalNormal,
        "Alertas",
        channelDescription: "Avisos de procesos fuera del horario de guardia (o guardia desarmada)",
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(interruptionLevel: InterruptionLevel.active),
    ),
    payload: jsonEncode({
      "titulo": titulo,
      "mensaje": cuerpo,
      "alarma": false,
      "esDemorado": esDemorado,
    }),
  );

  return false;
}

/// Manejador de mensajes con la app en segundo plano o cerrada del todo.
/// Debe ser una funcion de nivel superior (no un metodo de clase): FCM la
/// corre en un isolate NUEVO Y SEPARADO (motor de Flutter propio), sin nada
/// del estado inicializado en main() -por eso `_plugin` aca es una instancia
/// distinta a la que uso el isolate principal, y hay que inicializarla nueva
/// antes de poder mostrar nada, o `.show()` no hace nada.
@pragma("vm:entry-point")
Future<void> manejarMensajeEnSegundoPlano(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings("@mipmap/ic_launcher"),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _mostrarNotificacionDeAlarma(message);
  } catch (e, st) {
    debugPrint("Fallo mostrando alarma en segundo plano: $e\n$st");
    await _mostrarErrorDiagnostico("Segundo plano: $e");
  }
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

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(canalAlarmas);
    } on PlatformException catch (e) {
      // No dejar que un tono roto tumbe el arranque de la app: el canal se
      // vuelve a intentar crear (y cae al de sonido del sistema si hace
      // falta) recien cuando llegue una alarma real, en mostrarAlarmaLocal.
      if (e.code != "invalid_sound") rethrow;
    }

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
      try {
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
      } catch (e, st) {
        debugPrint("Fallo mostrando alarma en primer plano: $e\n$st");
        await _mostrarErrorDiagnostico("Primer plano: $e");
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
