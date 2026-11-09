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
