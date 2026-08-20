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

const String _idCanalNormal = "alertas_normales_v1";

// Sonido de alarma predeterminado del sistema (el mismo que usa el reloj
// despertador de Android): siempre existe en el dispositivo donde se
// instale, a diferencia de un tono propio empaquetado como recurso raw (que
// puede faltar en una instalacion vieja, un resource shrinking agresivo,
// etc. - la fuente del error "invalid_sound" que rompia la alarma entera).
// Se usa si el usuario no elige un tono propio del selector nativo (ver
// tono_alarma_service.dart) en Configuracion de Guardia.
const String _uriSonidoAlarmaSistema = "content://settings/system/alarm_alert";

// El id de canal esta atado para siempre al sonido/audio attributes que
// tenia la PRIMERA vez que Android lo creo (no se puede reconfigurar
// despues). Como el usuario puede elegir su propio tono, el id se deriva
// del sonido actual: cada tono distinto cae en un canal nuevo en vez de
// heredar el sonido de otro tono elegido antes (o de una version vieja de
// la app).
String _idCanalAlarmas(String sonidoUri) =>
    "alarmas_criticas_v4_${sonidoUri.hashCode.toRadixString(16)}";

AndroidNotificationChannel _canalAlarmas(String sonidoUri) => AndroidNotificationChannel(
      _idCanalAlarmas(sonidoUri),
      "Alarmas de control",
      description:
          "Alertas criticas cuando falla un proceso monitoreado, dentro del horario de guardia",
      importance: Importance.max,
      playSound: true,
      sound: UriAndroidNotificationSound(sonidoUri),
      enableVibration: true,
      // Trata el sonido como el de un despertador (volumen de alarma, no el
      // de notificaciones) para que suene tambien con el celular en
      // silencio/Do Not Disturb, igual que el reloj despertador del sistema.
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

Future<String> _sonidoAlarmaActual() async =>
    await GuardiaService().obtenerTonoUri() ?? _uriSonidoAlarmaSistema;

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

// Notification.FLAG_INSISTENT: repite sonido/vibracion en loop hasta que la
// notificacion se cancele. Esto es lo que hace que la alarma suene sin parar
// -con el sonido de alarma del propio sistema, no un archivo que reproduzca
// la app- de forma nativa, sin depender de que el motor de Flutter este
// corriendo para loopear un audio (por eso funciona igual con la app
// cerrada). apagarAlarmaLocal() es lo que hay que llamar para que pare.
const _flagInsistente = 4;

/// Muestra la alarma de pantalla completa A MANO (en vez de dejar que FCM la
/// muestre sola), porque solo asi se le puede pedir pantalla completa
/// (`fullScreenIntent`): eso es lo que hace que Android la lance directo
/// sobre la pantalla de bloqueo, como una alarma real. Publica (no privada)
/// porque tambien la usa `guardia_foreground_task.dart` como via de
/// respaldo: si Android mata la app y nunca llega a procesar el push (mas
/// comun de lo que deberia en Xiaomi/Samsung/Huawei sin autoarranque), el
/// Foreground Service -que tiene mucha mas proteccion contra esos mismos
/// bloqueos- puede disparar esta misma alarma el mismo, sin depender de FCM.
NotificationDetails _detallesAlarma(bool esDemorado, String sonidoUri) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      _idCanalAlarmas(sonidoUri),
      "Alarmas de control",
      channelDescription:
          "Alertas criticas cuando falla un proceso monitoreado, dentro del horario de guardia",
      importance: Importance.max,
      priority: Priority.max,
      sound: UriAndroidNotificationSound(sonidoUri),
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      additionalFlags: Int32List.fromList(<int>[_flagInsistente]),
      color: esDemorado ? StatusColors.advertencia : StatusColors.critico,
      colorized: true,
    ),
    iOS: const DarwinNotificationDetails(
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
    "id": id,
    "titulo": titulo,
    "mensaje": mensaje,
    "alarma": true,
    "esDemorado": esDemorado,
  });

  final sonidoUri = await _sonidoAlarmaActual();
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_canalAlarmas(sonidoUri));
  await _plugin.show(
    id,
    titulo,
    mensaje,
    _detallesAlarma(esDemorado, sonidoUri),
    payload: payload,
  );

  // Para que la notificacion persistente de guardia refleje esta falla
  // apenas ocurre, sin esperar su proximo tick.
  await registrarFallaParaNotificacionPersistente(mensaje);
}

/// Cancela cualquier alarma activa en este momento (todas las notificaciones
/// de esta app, no solo una por id): se usa al desarmar la guardia, para que
/// si una alarma ya estaba sonando insistente, apagar guardia la corte al
/// toque en vez de dejarla sonando hasta que alguien la apague a mano desde
/// la pantalla de alarma.
Future<void> apagarTodasLasAlarmasActivas() => _plugin.cancelAll();

/// Cancela la notificacion insistente: sin esto, aunque el usuario cierre la
/// pantalla de alarma, Android sigue repitiendo el sonido porque la
/// notificacion (FLAG_INSISTENT) sigue activa. Se llama al tocar "APAGAR
/// ALARMA" en AlarmaPushScreen.
Future<void> apagarAlarmaLocal(int id) => _plugin.cancel(id);

const int _idNotificacionResumenNoCore = 888888;

/// Notificacion sin sonido de alarma ni pantalla completa: la de un proceso
/// core fuera del horario/armado de guardia, o el resumen agregado de
/// procesos no-core (ver revisar_resumen_no_core en el backend).
Future<void> _mostrarNotificacionNormal({
  required int id,
  required String titulo,
  required String cuerpo,
  required bool esDemorado,
  required bool esAlarma,
}) async {
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(canalNormal);

  await _plugin.show(
    id,
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
      "alarma": esAlarma,
      "esDemorado": esDemorado,
    }),
  );
}

/// Recordatorio de que un proceso CORE sigue en error, sin sonido de alarma
/// (ver `_revisarAlarmaDeRespaldo` en guardia_foreground_task.dart: la alarma
/// sonora se limita a la deteccion y despues cada hora que siga fallando;
/// este recordatorio aparte se manda cada 30 min para que quede visible sin
/// hacer sonar la alarma esa cantidad de veces). Usa un id de notificacion
/// distinto al de la alarma del mismo proceso -si compartieran id, mostrar
/// esta reemplazaria la notificacion insistente de la alarma sonora y la
/// cortaria de golpe.
Future<void> mostrarRecordatorioDeError({
  required int id,
  required String titulo,
  required String mensaje,
  required bool esDemorado,
}) =>
    _mostrarNotificacionNormal(
      id: id + 1000000,
      titulo: titulo,
      cuerpo: mensaje,
      esDemorado: esDemorado,
      esAlarma: false,
    );

/// Muestra la notificacion que llega por push A MANO. Devuelve `true` si se
/// mostro como alarma de pantalla completa (para que el llamador decida si
/// conviene ademas navegar directo a esa pantalla). Funciona igual la llame
/// el listener de primer plano o el manejador de segundo plano.
Future<bool> _mostrarNotificacionDeAlarma(RemoteMessage message) async {
  final tipo = message.data["tipo"];

  if (tipo == "resumen_no_core") {
    // Agregado de procesos NO core: nunca es alarma de pantalla completa,
    // sin importar horario/armado de guardia -es solo informativo. Id fijo
    // para que cada resumen nuevo REEMPLACE al anterior en la bandeja en vez
    // de acumularse.
    await _mostrarNotificacionNormal(
      id: _idNotificacionResumenNoCore,
      titulo: message.data["titulo"] ?? "Procesos no-core",
      cuerpo: message.data["mensaje"] ?? "",
      esDemorado: false,
      esAlarma: false,
    );
    return false;
  }

  if (tipo == "alerta_normal") {
    // Aviso que no amerita alarma (p.ej. fallo silencioso de incoherencia
    // proceso/tabla): siempre notificacion comun, sin importar horario ni
    // armado de guardia.
    await _mostrarNotificacionNormal(
      id: message.hashCode,
      titulo: message.data["titulo"] ?? "Alerta",
      cuerpo: message.data["mensaje"] ?? "",
      esDemorado: false,
      esAlarma: false,
    );
    return false;
  }

  if (tipo != "alerta_critica") return false;

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

  await _mostrarNotificacionNormal(
    id: message.hashCode,
    titulo: titulo,
    cuerpo: cuerpo,
    esDemorado: esDemorado,
    esAlarma: false,
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
      id: datos["id"] as int? ?? 0,
      titulo: datos["titulo"] as String? ?? "Alerta crítica",
      mensaje: datos["mensaje"] as String? ?? "",
      esDemorado: datos["esDemorado"] == true,
      // Se llega aca por tocar la notificacion o porque Android lanzo la
      // app solo (fullScreenIntent con el celular bloqueado) - nunca porque
      // la app ya estaba abierta y la alarma la interrumpio.
      esLanzamiento: true,
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

    final sonidoUri = await _sonidoAlarmaActual();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_canalAlarmas(sonidoUri));

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
            id: message.hashCode,
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

    // inicializar() se llama sin condicion en cada login (login_screen,
    // configurar_password_screen): sin este chequeo, un usuario que apago
    // notificaciones desde Ajustes las recibia de nuevo apenas volvia a
    // entrar, porque este metodo pedia permiso y re-registraba el token en
    // el servidor sin mirar la preferencia guardada. La alarma local de
    // Guardia no se ve afectada: ya quedo lista arriba, en
    // inicializarTemprano().
    if (!await GuardiaService().obtenerNotificacionesHabilitadas()) return;

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

    final token = await _obtenerTokenConReintentos(messaging);
    if (token != null) {
      try {
        await _apiService.registrarFcmToken(token);
        await GuardiaService().guardarDiagnosticoFcm("ok");
      } catch (e) {
        await GuardiaService().guardarDiagnosticoFcm("Token obtenido pero el backend lo rechazo: $e");
      }
    }
    messaging.onTokenRefresh.listen(_apiService.registrarFcmToken);
  }

  /// getToken() puede devolver null o tirar una excepcion transitoria justo
  /// despues de instalar/actualizar la app (Play Services todavia
  /// terminando de registrarse). Sin este reintento, esa primera falla
  /// quedaba silenciosa para siempre hasta el proximo login. Si tras los 3
  /// intentos sigue sin token, el motivo real (el de la ultima excepcion, o
  /// "getToken devolvio null") queda guardado para poder verlo en Ajustes.
  Future<String?> _obtenerTokenConReintentos(FirebaseMessaging messaging) async {
    Object? ultimoError;
    for (var intento = 0; intento < 3; intento++) {
      try {
        final token = await messaging.getToken();
        if (token != null) return token;
        ultimoError = "getToken() devolvio null";
      } catch (e) {
        ultimoError = e;
      }
      if (intento < 2) await Future.delayed(Duration(seconds: 3 * (intento + 1)));
    }
    await GuardiaService().guardarDiagnosticoFcm("No se pudo obtener el token FCM: $ultimoError");
    return null;
  }
}
