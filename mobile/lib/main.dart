import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "screens/login_screen.dart";
import "theme.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La version web necesita su propia configuracion de Firebase (pendiente);
  // se omite ahi por ahora para poder probar login/dashboard sin bloquear.
  if (!kIsWeb) {
    await Firebase.initializeApp();
  }

  runApp(const AppControles());
}

class AppControles extends StatelessWidget {
  const AppControles({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
