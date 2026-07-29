import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "screens/login_screen.dart";
import "services/guardia_foreground_task.dart";
import "services/navegacion_service.dart";
import "services/notification_service.dart";
import "theme.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La version web necesita su propia configuracion de Firebase (pendiente);
  // se omite ahi por ahora para poder probar login/dashboard sin bloquear.
  if (!kIsWeb) {
    await Firebase.initializeApp();
    // Deja el canal de alarma y los listeners de FCM listos ANTES del login,
    // para poder recibir/mostrar la alarma incluso si el usuario todavia no
    // entro (o si la app fue lanzada por Android al tocar la notificacion).
    await NotificationService().inicializarTemprano();
    inicializarForegroundTask();
  }

  runApp(const AppControles());
}

class AppControles extends StatefulWidget {
  const AppControles({super.key});

  @override
  State<AppControles> createState() => _AppControlesState();
}

class _AppControlesState extends State<AppControles> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().revisarLanzamientoPorAlarma();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NavegacionService.navigatorKey,
      title: "Controles",
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      // LoginScreen decide sola entre mostrar Google o el desbloqueo con
      // huella/Face ID, segun si ya hay una sesion guardada.
      home: const LoginScreen(),
    );
  }
}
