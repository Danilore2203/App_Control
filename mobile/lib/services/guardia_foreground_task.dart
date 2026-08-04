import "dart:async";
import "dart:convert";

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
const _claveEstadoAlarmas = "guardia_estado_alarmas";
const _claveIdsReconocidos = "guardia_ids_reconocidos";

// La alarma sonora se repite mientras el proceso siga en error, pero no en
// cada corrida (cada 2 min seria insoportable): solo al detectarlo y despues
// cada vez que pase esta duracion. El recordatorio silencioso es mas
// frecuente porque no interrumpe con sonido.
const _duracionEntreAlarmas = Duration(hours: 1);
const _duracionEntreRecordatorios = Duration(minutes: 30);

/// Llamado desde `_mostrarNotificacionDeAlarma` (notification_service.dart)
/// cada vez que llega una alerta critica real, para que la proxima vez que
/// la notificacion persistente se actualice (o el usuario la mire) ya
/// refleje esta falla, sin esperar el proximo tick del servicio.
Future<void> registrarFallaParaNotificacionPersistente(String mensaje) async {
  final actual = await FlutterForegroundTask.getData<int>(key: _claveContadorFallas) ?? 0;
  await FlutterForegroundTask.saveData(key: _claveContadorFallas, value: actual + 1);
  await FlutterForegroundTask.saveData(key: _claveUltimoMensaje, value: mensaje);
}

/// Llamado desde el boton "Error corregido" en AlarmaPushScreen: el usuario
/// confirma a mano que ya se solucino, asi que se deja de alarmar/recordar
/// para este proceso aunque el origen todavia no reporte verde -algunos
/// tardan en reflejarlo. Se "olvida" el reconocimiento apenas el proceso
/// realmente vuelve a verde (ver _revisarAlarmaDeRespaldo), para que si
/// vuelve a fallar despues se alarme de nuevo como falla nueva.
Future<void> marcarErrorCorregido(int controlId) async {
  final reconocidosTexto = await FlutterForegroundTask.getData<String>(key: _claveIdsReconocidos) ?? "";
  final reconocidos = reconocidosTexto.isEmpty
      ? <int>{}
      : reconocidosTexto.split(",").map(int.parse).toSet();
  reconocidos.add(controlId);
  await FlutterForegroundTask.saveData(key: _claveIdsReconocidos, value: reconocidos.join(","));
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
      FlutterForegroundTask.removeData(key: _claveEstadoAlarmas),
      FlutterForegroundTask.removeData(key: _claveIdsReconocidos),
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
  /// local directo, sin esperar a que llegue (o no) el push.
  ///
  /// La alarma sonora no se repite cada 2 min mientras siga la misma falla
  /// (seria insoportable): suena al detectarla y, si sigue en error, otra
  /// vez cada _duracionEntreAlarmas. Aparte, cada _duracionEntreRecordatorios
  /// se manda un recordatorio silencioso (sin sonido de alarma) para que
  /// quede visible que sigue sin resolverse. Todo esto se "olvida" recien
  /// cuando el proceso vuelve a verde (exito real) o el usuario confirma a
  /// mano "Error corregido" (ver marcarErrorCorregido), para que si vuelve a
  /// fallar despues se trate como falla nueva.
  Future<void> _revisarAlarmaDeRespaldo(List<Control> controles) async {
    final coreControles = controles.where(esCore).toList();
    final fallandoCore = coreControles.where((c) => c.color == "red" || c.color == "orange");
    // No alcanza con el color: si la fuente manda color verde pero el
    // estado crudo no confirma "OK", es una inconsistencia de los datos de
    // origen, no un exito real -se sigue alertando hasta que el estado
    // tambien confirme (mismo criterio que recuperado_confirmado en el
    // backend, poller.py).
    final recuperados = coreControles
        .where((c) => c.color == "green" && c.estado.trim().toUpperCase() == "OK")
        .map((c) => c.id)
        .toSet();

    final estadoTexto = await FlutterForegroundTask.getData<String>(key: _claveEstadoAlarmas) ?? "{}";
    final estado = Map<String, dynamic>.from(jsonDecode(estadoTexto) as Map);

    final reconocidosTexto = await FlutterForegroundTask.getData<String>(key: _claveIdsReconocidos) ?? "";
    final reconocidos = reconocidosTexto.isEmpty
        ? <int>{}
        : reconocidosTexto.split(",").map(int.parse).toSet();

    final ahora = DateTime.now();

    for (final control in fallandoCore) {
      // fallandoCore ya viene filtrado por esCore: todos los que llegan aca
      // son procesos core.
      if (reconocidos.contains(control.id)) continue;

      final clave = control.id.toString();
      final registro = estado[clave] as Map<String, dynamic>?;

      if (registro == null) {
        await mostrarAlarmaLocal(
          id: control.id,
          titulo: "Alerta de proceso CORE",
          mensaje: "[${control.fuente}] ${control.nombre}: ${control.estado}",
          esDemorado: control.esDemorado,
        );
        estado[clave] = {
          "ultimaAlarma": ahora.toIso8601String(),
          "ultimoRecordatorio": ahora.toIso8601String(),
        };
        continue;
      }

      final ultimaAlarma = DateTime.parse(registro["ultimaAlarma"] as String);
      if (ahora.difference(ultimaAlarma) >= _duracionEntreAlarmas) {
        await mostrarAlarmaLocal(
          id: control.id,
          titulo: "Alerta de proceso CORE",
          mensaje: "[${control.fuente}] ${control.nombre}: ${control.estado}",
          esDemorado: control.esDemorado,
        );
        registro["ultimaAlarma"] = ahora.toIso8601String();
        registro["ultimoRecordatorio"] = ahora.toIso8601String();
        continue;
      }

      final ultimoRecordatorio = DateTime.parse(registro["ultimoRecordatorio"] as String);
      if (ahora.difference(ultimoRecordatorio) >= _duracionEntreRecordatorios) {
        await mostrarRecordatorioDeError(
          id: control.id,
          titulo: "Proceso CORE sigue en error",
          mensaje: "[${control.fuente}] ${control.nombre}: ${control.estado}",
          esDemorado: control.esDemorado,
        );
        registro["ultimoRecordatorio"] = ahora.toIso8601String();
      }
    }

    // No se toca el registro de un control con color transitorio (p.ej.
    // "blue"/en ejecucion durante un reintento del origen): no es
    // rojo/naranja, pero tampoco es el exito real que debe "perdonarlo".
    // Solo se olvida (estado + reconocimiento manual) cuando aparece
    // explicitamente en verde.
    for (final id in recuperados) {
      estado.remove(id.toString());
      reconocidos.remove(id);
    }

    await FlutterForegroundTask.saveData(key: _claveEstadoAlarmas, value: jsonEncode(estado));
    await FlutterForegroundTask.saveData(key: _claveIdsReconocidos, value: reconocidos.join(","));
  }
}
