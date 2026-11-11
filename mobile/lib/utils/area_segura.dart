// Muesca y barra de inicio del iPhone en la version web (Safari / pantalla de
// inicio): Flutter web no las informa (MediaQuery.padding siempre es cero), asi
// que se leen del CSS env(safe-area-inset-*) que mide web/index.html.
export "area_segura_stub.dart" if (dart.library.js_interop) "area_segura_web.dart";
