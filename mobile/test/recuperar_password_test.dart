import "package:app_controles/screens/recuperar_password_screen.dart";
import "package:app_controles/services/auth_service.dart";
import "package:app_controles/theme.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";

class _AuthFalso extends AuthService {
  final pedidos = <String>[];
  final cambios = <(String, String, String)>[];

  @override
  Future<({bool ok, String mensaje})> solicitarRecuperacion(String identificador) async {
    pedidos.add(identificador);
    return (ok: true, mensaje: "Si la cuenta existe, en unos minutos te llega un código.");
  }

  @override
  Future<void> restablecerPassword({
    required String identificador,
    required String codigo,
    required String passwordNueva,
  }) async {
    cambios.add((identificador, codigo, passwordNueva));
    throw Exception("El código no es válido o ya venció. Pide uno nuevo.");
  }
}

void main() {
  setUpAll(() {
    AppTheme.usarGoogleFonts = false;
    PackageInfo.setMockInitialValues(
        appName: "x", packageName: "x", version: "1.0.0", buildNumber: "1", buildSignature: "");
  });

  testWidgets("pide el código, luego código y contraseña nueva, y muestra el error del backend", (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final auth = _AuthFalso();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: RecuperarPasswordScreen(servicio: auth)));

    // Paso 1: sin usuario no pide nada.
    await tester.tap(find.text("Enviar código"));
    await tester.pump();
    expect(find.text("Escribe tu usuario o tu correo"), findsOneWidget);
    expect(auth.pedidos, isEmpty);

    await tester.enterText(find.byKey(const Key("recuperar_usuario")), "  aperez ");
    await tester.tap(find.text("Enviar código"));
    await tester.pump();
    await tester.pump();
    expect(auth.pedidos, ["aperez"]);

    // Paso 2.
    expect(find.text("Revisa tu correo"), findsOneWidget);
    expect(find.textContaining("te llega un código"), findsOneWidget);
    expect(find.text("Reenviar en 60 s"), findsOneWidget);

    // El código solo acepta 6 dígitos.
    await tester.enterText(find.byKey(const Key("recuperar_codigo")), "12a34567");
    expect(tester.widget<TextField>(find.descendant(
        of: find.byKey(const Key("recuperar_codigo")), matching: find.byType(TextField))).controller!.text, "123456");

    await tester.enterText(find.byKey(const Key("recuperar_nueva")), "Nueva#2026");
    await tester.enterText(find.byKey(const Key("recuperar_confirmar")), "Otra#2026");
    await tester.ensureVisible(find.text("Cambiar y entrar"));
    await tester.tap(find.text("Cambiar y entrar"));
    await tester.pump();
    expect(find.text("Las contraseñas no coinciden"), findsOneWidget);
    expect(auth.cambios, isEmpty);

    await tester.enterText(find.byKey(const Key("recuperar_confirmar")), "Nueva#2026");
    await tester.tap(find.text("Cambiar y entrar"));
    await tester.pump();
    await tester.pump();
    expect(auth.cambios, [("aperez", "123456", "Nueva#2026")]);
    expect(find.textContaining("no es válido o ya venció"), findsOneWidget);

    // Tras la espera se puede reenviar.
    await tester.pump(const Duration(seconds: 61));
    expect(find.text("¿No llegó? Reenviar código"), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox()); // cancela el temporizador
  });

  testWidgets("con «Ya tengo un código» no pide correo ni ofrece reenviar (anularía el del administrador)",
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final auth = _AuthFalso();
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: RecuperarPasswordScreen(servicio: auth, usuarioInicial: "jhojrodriguez")));
    await tester.tap(find.byKey(const Key("ya_tengo_codigo")));
    await tester.pump();

    expect(auth.pedidos, isEmpty);
    expect(find.text("Escribe tu código"), findsOneWidget);
    expect(find.textContaining("te dio un administrador"), findsOneWidget);
    expect(find.textContaining("Reenviar"), findsNothing);

    await tester.enterText(find.byKey(const Key("recuperar_codigo")), "654321");
    await tester.enterText(find.byKey(const Key("recuperar_nueva")), "Nueva#2026");
    await tester.enterText(find.byKey(const Key("recuperar_confirmar")), "Nueva#2026");
    await tester.ensureVisible(find.text("Cambiar y entrar"));
    await tester.tap(find.text("Cambiar y entrar"));
    await tester.pump();
    await tester.pump();
    expect(auth.cambios, [("jhojrodriguez", "654321", "Nueva#2026")]);
    expect(tester.takeException(), isNull);
  });
}
