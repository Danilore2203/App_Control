import "dart:async";

import "package:flutter_foreground_task/flutter_foreground_task.dart";

import "../models/control.dart";
import "../widgets/monitoreo_por_fuente.dart" show esCore;
import "api_service.dart";
import "guardia_service.dart";
import "notification_service.dart";

const String _idServicioGuardia = "guardia_activa_v1";
const int _idNotificacionGuardia = 4001;

const _claveContadorFallas = "guardia_contador_fallas";
const _claveUltimoMensaje = "guardia_ultimo_mensaje";
const _claveIdsAlarmados = "guardia_ids_alarmados";

/// Llamado desde `_mostrarNotificacionDeAlarma` (notification_service.dart)
/// cada vez que llega una alerta critica real, para que la proxima vez que
/// la notificacion persistente se actualice (o el usuario la mire) ya
/// refleje esta falla, sin esperar el proximo tick del servicio.
Future<void> registrarFallaParaNotificacionPersistente(String mensaje) async {
  final actual = await FlutterForegroundTask.getData<int>(key: _claveContadorFallas) ?? 0;
  await FlutterForegroundTask.saveData(key: _claveContadorFallas, value: actual + 1);
  await FlutterForegroundTask.saveData(key: _claveUltimoMensaje, value: mensaje);
}

/// Se llama una sola vez, apenas arranca la app (igual que
/// NotificationService.inicializarTemprano), antes de poder arrancar/parar
/// el servicio.
void inicializarForegroundTask() {
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: _idServicioGuardia,
      channelName: "Guardia activa",
      channelDescription: "Notificación fija mientras la guardia está armada, con el estado del monitoreo",
      channelImportance: NotificationChannelImportance.DEFAULT,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(120000), // cada 2 min
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

/// Arranca o para la notificación persistente de guardia. Se llama desde el
/// mismo switch "armado" de Configuración de Guardia (ver plan: usar el
/// horario para el contenido, no para programar el arranque exacto, que es
/// mucho menos confiable en Android).
Future<void> _detenerServicioSiCorre() async {
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.stopService();
  }
}

Future<void> establecerGuardiaActiva(bool activa) async {
  if (!activa) {
    // Primero lo mas urgente/perceptible (cortar sonido si algo esta
    // sonando), sin esperar a las tareas mas lentas del apagado del
    // servicio -antes se hacia al final y en secuencia, sumando el retraso
    // de cada paso antes de que el usuario notara ALGO cambiar.
    unawaited(apagarTodasLasAlarmasActivas());
    await Future.wait<void>([
      _detenerServicioSiCorre(),
      FlutterForegroundTask.removeData(key: _claveContadorFallas),
      FlutterForegroundTask.removeData(key: _claveUltimoMensaje),
      FlutterForegroundTask.removeData(key: _claveIdsAlarmados),
    ]);
    return;
  }

  final permiso = await FlutterForegroundTask.checkNotificationPermission();
  if (permiso != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.restartService();
  } else {
    await FlutterForegroundTask.startService(
      serviceId: _idNotificacionGuardia,
      notificationTitle: "Guardia activa",
      notificationText: "Iniciando monitoreo…",
      callback: _iniciarTareaDeGuardia,
    );
  }
}

// El callback siempre debe ser una funcion de nivel superior (no un metodo).
@pragma("vm:entry-point")
void _iniciarTareaDeGuardia() {
  FlutterForegroundTask.setTaskHandler(_GuardiaTaskHandler());
}

class _GuardiaTaskHandler extends TaskHandler {
  final _apiService = ApiService();
  final _guardiaService = GuardiaService();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _actualizarNotificacion();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _actualizarNotificacion();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}

  Future<void> _actualizarNotificacion() async {
    final inicio = await _guardiaService.obtenerHoraInicio();
    final fin = await _guardiaService.obtenerHoraFin();
    final dentro = _guardiaService.estaDentroDeHorario(DateTime.now(), inicio, fin);
    final estadoHorario = dentro ? "Dentro de horario" : "Fuera de horario";

    String textoEstado;
    try {
      final controles = await _apiService.obtenerControles();
      final fallando = controles.where((c) => c.color == "red" || c.color == "orange").length;
      textoEstado = fallando == 0
          ? "Todo OK"
          : "$fallando proceso${fallando == 1 ? '' : 's'} con falla";

      if (dentro) await _revisarAlarmaDeRespaldo(controles);
    } catch (_) {
      textoEstado = "No se pudo consultar el estado";
    }

    final contador = await FlutterForegroundTask.getData<int>(key: _claveContadorFallas) ?? 0;
    final ultimoMensaje = await FlutterForegroundTask.getData<String>(key: _claveUltimoMensaje);

    final partes = [
      "$estadoHorario ($inicio–$fin)",
      textoEstado,
      if (contador > 0) "$contador detectada${contador == 1 ? '' : 's'} en esta guardia",
      if (ultimoMensaje != null && ultimoMensaje.isNotEmpty) "Último: $ultimoMensaje",
    ];

    await FlutterForegroundTask.updateService(
      notificationTitle: "Guardia activa",
      notificationText: partes.join(" · "),
    );
  }

  /// Via de respaldo, independiente del push de Firebase: este Foreground
  /// Service ya esta corriendo cada 2 min de por si (con mucha mas
  /// proteccion contra los bloqueos de bateria/autoarranque de fabrica que
  /// revivir una app muerta via FCM), asi que aprovecha esa misma corrida
  /// para detectar procesos core en falla EL MISMO y disparar la alarma
  /// local directo, sin esperar a que llegue (o no) el push. Guarda que ids
  /// ya alarmo para no repetir cada 2 min mientras siga la misma falla, y
  /// los "olvida" apenas el proceso se recupera, para que si vuelve a
  /// fallar despues se alarme de nuevo.
  Future<void> _revisarAlarmaDeRespaldo(List<Control> controles) async {
    final fallandoCore = controles
        .where(esCore)
        .where((c) => c.color == "red" || c.color == "orange")
        .toList();

    final previosTexto = await FlutterForegroundTask.getData<String>(key: _claveIdsAlarmados) ?? "";
    final previos = previosTexto.isEmpty
        ? <int>{}
        : previosTexto.split(",").map(int.parse).toSet();

    final actuales = fallandoCore.map((c) => c.id).toSet();
    final nuevos = fallandoCore.where((c) => !previos.contains(c.id));

    for (final control in nuevos) {
      // fallandoCore ya viene filtrado por esCore: todos los que llegan aca
      // son procesos core.
      await mostrarAlarmaLocal(
        id: control.id,
        titulo: "Alerta de proceso CORE",
        mensaje: "[${control.fuente}] ${control.nombre}: ${control.estado}",
        esDemorado: control.esDemorado,
      );
    }

    await FlutterForegroundTask.saveData(key: _claveIdsAlarmados, value: actuales.join(","));
  }
}
