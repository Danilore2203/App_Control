import "package:app_controles/models/usuario.dart";
import "package:app_controles/screens/usuarios_admin_screen.dart";
import "package:app_controles/services/api_service.dart";
import "package:app_controles/theme.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

class _ApiFalsa extends ApiService {
  final busquedas = <String>[];
  final generados = <int>[];

  @override
  Future<List<Usuario>> buscarUsuarios(String texto) async {
    busquedas.add(texto);
    return [
      Usuario(
          id: 7,
          username: "jhojrodriguez",
          nombre: "Jhojans Rodriguez",
          email: "Jhojans.Rodriguez@nuevatel.com",
          activo: true,
          esAdmin: false),
      Usuario(id: 8, username: "baja", activo: false, esAdmin: false),
    ];
  }

  @override
  Future<({String codigo, int minutos, DateTime expiraEn})> generarCodigoRecuperacion(int usuarioId) async {
    generados.add(usuarioId);
    return (codigo: "482913", minutos: 30, expiraEn: DateTime(2026, 11, 10, 15, 30));
  }
}

void main() {
  setUpAll(() => AppTheme.usarGoogleFonts = false);

  testWidgets("busca, genera el código para la persona y muestra qué tiene que hacer", (tester) async {
    final api = _ApiFalsa();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: UsuariosAdminScreen(servicio: api)));
    await tester.pump();
    expect(find.text("Jhojans Rodriguez"), findsOneWidget);
    expect(find.text("Inactiva"), findsOneWidget);

    await tester.enterText(find.byKey(const Key("buscar_usuarios")), "jhoj");
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(api.busquedas, ["", "jhoj"]);

    // La cuenta inactiva no permite generar código.
    final botones = tester
        .widgetList<IconButton>(find.ancestor(of: find.byIcon(Icons.key_rounded), matching: find.byType(IconButton)))
        .toList();
    expect(botones.map((b) => b.onPressed != null).toList(), [true, false]);

    await tester.tap(find.byIcon(Icons.key_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text("Generar"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(api.generados, [7]);
    expect(find.byKey(const Key("codigo_generado")), findsOneWidget);
    expect(find.text("482913"), findsOneWidget);
    expect(find.textContaining("hasta las 15:30"), findsOneWidget);
    expect(find.textContaining("«Ya tengo un código»"), findsOneWidget);
    await tester.tap(find.text("Listo"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("482913"), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
