// Smoke test minimo: el test por defecto de Flutter (contador +1) quedo sin
// tocar desde `flutter create`, importando una clase `MyApp` que no existe
// en este proyecto (la app se llama `AppControles`) - no compilaba nunca.
//
// Reemplazado por una verificacion real, aunque chica, de los temas de la
// app. Una suite de tests de verdad (servicios, parseo de modelos) es una
// mejora aparte, mas grande, pendiente.

import "package:app_controles/theme.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("AppTheme expone temas claro y oscuro coherentes", () {
    expect(AppTheme.light.useMaterial3, isTrue);
    expect(AppTheme.dark.useMaterial3, isTrue);
    expect(AppTheme.light.brightness, Brightness.light);
    expect(AppTheme.dark.brightness, Brightness.dark);
  });
}
