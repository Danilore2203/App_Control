/// Numero que puede venir como texto: MySQL devuelve DECIMAL y el JSON lo
/// trae como "1234.00". Entero si no tiene decimales; null si no es numero.
num? leerNumero(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  final n = num.tryParse(v.toString().trim());
  if (n == null) return null;
  return n == n.truncate() ? n.toInt() : n;
}

/// Entero con separador de miles al estilo local ("11.375", "100.592").
String formatearMiles(int n) {
  final digitos = n.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    final restantes = digitos.length - i;
    buffer.write(digitos[i]);
    if (restantes > 1 && restantes % 3 == 1) buffer.write(".");
  }
  return n < 0 ? "-$buffer" : buffer.toString();
}
