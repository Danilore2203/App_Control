import "dart:js_interop";

import "package:flutter/widgets.dart";

@JS("leerAreaSegura")
external JSObject? _leerAreaSegura();

extension type _Area(JSObject _) implements JSObject {
  external double get top;
  external double get right;
  external double get bottom;
  external double get left;
}

/// Lo que mide `leerAreaSegura()` de web/index.html (en px CSS = logicos).
EdgeInsets areaSeguraWeb() {
  try {
    final o = _leerAreaSegura();
    if (o == null) return EdgeInsets.zero;
    final a = _Area(o);
    return EdgeInsets.fromLTRB(a.left, a.top, a.right, a.bottom);
  } catch (_) {
    return EdgeInsets.zero;
  }
}
