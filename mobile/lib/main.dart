import "dart:math" as math;

import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "screens/login_screen.dart";
import "services/guardia_foreground_task.dart";
import "services/navegacion_service.dart";
import "services/notification_service.dart";
import "theme.dart";
import "utils/area_segura.dart";
import "widgets/fondo_app.dart";

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

/// Solo en la version web (Safari en iPhone, o una computadora):
/// - Muesca y barra de inicio: Flutter web no las informa, asi que se pasan a
///   MediaQuery para que la barra de arriba y la de abajo no queden debajo.
/// - Pantallas anchas (iPad, computadora): la app se ve como en el celular,
///   centrada, en vez de estirarse a todo el ancho.
Widget _ajusteWeb(BuildContext context, Widget child) {
  if (!kIsWeb) return child;
  final mq = MediaQuery.of(context);
  final area = areaSeguraWeb();
  var datos = mq.copyWith(
    padding: EdgeInsets.fromLTRB(
      math.max(mq.padding.left, area.left),
      math.max(mq.padding.top, area.top),
      math.max(mq.padding.right, area.right),
      math.max(mq.padding.bottom, area.bottom),
    ),
  );
  datos = datos.copyWith(viewPadding: datos.padding);
  const anchoMaximo = 560.0;
  if (mq.size.width <= anchoMaximo + 160) return MediaQuery(data: datos, child: child);
  return Center(
    child: SizedBox(
      width: anchoMaximo,
      child: MediaQuery(data: datos.copyWith(size: Size(anchoMaximo, mq.size.height)), child: child),
    ),
  );
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
      // Fondo comun (gradiente + brillo lima + puntos) detras de todas las
      // pantallas; los Scaffold van transparentes (ver AppTheme).
      builder: (context, child) => FondoApp(child: _ajusteWeb(context, child ?? const SizedBox.shrink())),
      // LoginScreen decide sola entre mostrar Google o el desbloqueo con
      // huella/Face ID, segun si ya hay una sesion guardada.
      home: const LoginScreen(),
    );
  }
}
