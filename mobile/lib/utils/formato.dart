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

/// «45 s», «12 min», «2 h 5 min» (como el monitor web).
String duracionCorta(num? segundos) {
  final s = segundos == null || segundos < 0 ? 0 : segundos.round();
  if (s < 60) return "$s s";
  final m = s ~/ 60;
  if (m < 60) return "$m min";
  final r = m % 60;
  return "${m ~/ 60} h${r > 0 ? " $r min" : ""}";
}

const _meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
final _reZonaFinal = RegExp(r"(Z|[+-]\d{2}:?\d{2})$");

String _dos(int n) => n.toString().padLeft(2, "0");

/// Fecha que el backend de App_Control guarda en UTC sin zona
/// (datetime.utcnow: alertas, solicitudes...), pasada a la hora del celular.
/// Sin esto se mostraba 4 horas adelantada.
DateTime fechaUtc(String valor) {
  final s = valor.trim();
  return DateTime.parse(_reZonaFinal.hasMatch(s) ? s : "${s}Z").toLocal();
}

/// «Hoy 14:00», «Ayer 15:15», «9 nov · 15:15», «24 oct 2024».
String fechaAmigable(DateTime f, {DateTime? ahora}) {
  final hoy = ahora ?? DateTime.now();
  final dias = DateTime(hoy.year, hoy.month, hoy.day).difference(DateTime(f.year, f.month, f.day)).inDays;
  final hora = "${_dos(f.hour)}:${_dos(f.minute)}";
  if (dias == 0) return "Hoy $hora";
  if (dias == 1) return "Ayer $hora";
  if (f.year == hoy.year) return "${f.day} ${_meses[f.month - 1]} · $hora";
  return "${f.day} ${_meses[f.month - 1]} ${f.year}";
}

/// «Hoy», «Ayer», «9 nov», «24 oct 2024»: encabezado para agrupar por dia.
String diaAmigable(DateTime f, {DateTime? ahora}) {
  final hoy = ahora ?? DateTime.now();
  final dias = DateTime(hoy.year, hoy.month, hoy.day).difference(DateTime(f.year, f.month, f.day)).inDays;
  if (dias == 0) return "Hoy";
  if (dias == 1) return "Ayer";
  if (f.year == hoy.year) return "${f.day} ${_meses[f.month - 1]}";
  return "${f.day} ${_meses[f.month - 1]} ${f.year}";
}

/// Fecha del catalogo tal como la manda OP_PROD («2026-11-10 14:00:05» o solo
/// «08:09:00»). No se cambia de zona: Airflow la manda en UTC y DataStage en
/// hora local, igual que la muestra la web.
DateTime? leerFechaCatalogo(String? v) {
  final s = (v ?? "").trim();
  if (s.length < 16 || s[4] != "-") return null;
  return DateTime.tryParse(s.substring(0, s.length >= 19 ? 19 : 16).replaceFirst(" ", "T"));
}

/// La fecha del catalogo legible: «Hoy 14:00», «9 nov · 15:15», o «08:09» si solo trae la hora.
String? fechaCatalogo(String? v, {DateTime? ahora}) {
  final s = (v ?? "").trim();
  if (s.isEmpty) return null;
  final f = leerFechaCatalogo(s);
  if (f != null) return fechaAmigable(f, ahora: ahora);
  final m = RegExp(r"^(\d{1,2}):(\d{2})").firstMatch(s);
  if (m != null) return "${m.group(1)!.padLeft(2, "0")}:${m.group(2)}";
  return s;
}

/// Cuanto tardo entre dos fechas del catalogo («12 min»), o null si no se puede saber.
String? duracionEntre(String? inicio, String? fin) {
  final a = leerFechaCatalogo(inicio);
  final b = leerFechaCatalogo(fin);
  if (a == null || b == null || b.isBefore(a)) return null;
  return duracionCorta(b.difference(a).inSeconds);
}
