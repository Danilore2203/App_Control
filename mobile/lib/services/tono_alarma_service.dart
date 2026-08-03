import "package:flutter/services.dart";

const _canalTonos = MethodChannel("app_controles/tonos");

/// Abre el selector nativo de tonos de Android (los mismos tonos de alarma
/// que ya estan en el celular, incluyendo cualquiera que el usuario haya
/// agregado) - no requiere empaquetar ningun archivo propio, asi que nunca
/// puede faltar como paso con un recurso raw. Devuelve el URI elegido, o
/// null si el usuario cancelo.
Future<String?> elegirTonoAlarmaDelSistema({String? uriActual}) {
  return _canalTonos.invokeMethod<String>(
    "elegirTonoAlarma",
    {"uriActual": uriActual},
  );
}

/// Nombre legible de un tono a partir de su URI (p.ej. "Sirena de alarma
/// clasica"). Android no expone esto salvo via RingtoneManager nativo. Null
/// si no se pudo resolver (tono desinstalado, URI invalido, etc.).
Future<String?> nombreTonoAlarma(String? uri) {
  if (uri == null) return Future.value(null);
  return _canalTonos.invokeMethod<String>("nombreTono", {"uri": uri});
}
