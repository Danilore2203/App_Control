import "formato.dart";

/// Una consulta en pocas palabras, como en el monitor web de Netezza: que
/// hace («Carga», «Borra», «Consulta»...) y sobre que tabla. La consulta
/// completa se ve aparte.
class ResumenSql {
  final String verbo;
  final String tabla;

  /// Tabla temporal de DataStage (NZCC_TT_...): se muestra el nombre real.
  final bool temporal;

  /// INSERT ... FROM EXTERNAL: Netezza carga lo que le manda el cliente.
  final bool externa;

  /// CREATE EXTERNAL TABLE ... AS SELECT: el cliente descarga filas.
  final bool descarga;

  const ResumenSql({this.verbo = "", this.tabla = "", this.temporal = false, this.externa = false, this.descarga = false});
}

const _verboTxt = {
  "INSERT": "Carga",
  "DELETE": "Borra",
  "UPDATE": "Actualiza",
  "TRUNCATE": "Vacía",
  "GROOM": "Groom",
  "ALTER": "Modifica",
  "DROP": "Elimina",
  "CREATE": "Crea",
  "GENERATE": "Estadísticas",
  "SELECT": "Consulta",
  "WITH": "Consulta",
  "CALL": "Ejecuta",
  "COMMIT": "Confirma",
};

final _reComillas = RegExp(r'''["']''');
final _reTemporal = RegExp(r"^(.*?)NZCC_TT_\d+_\d+_(.+)$", caseSensitive: false);
final _reEspacios = RegExp(r"\s+");
final _reExterna = RegExp(r"\bFROM EXTERNAL\b", caseSensitive: false);
final _reCrearExterna = RegExp(r"^CREATE EXTERNAL TABLE\s+(\S+)", caseSensitive: false);
final _reSelectFrom = RegExp(r'''\bSELECT\b.*?\bFROM\s+([A-Za-z_"][^\s,();]*)''', caseSensitive: false);
final _reVerboTabla = RegExp(
  r"^(INSERT INTO|DELETE FROM|UPDATE|TRUNCATE(?: TABLE)?|GROOM TABLE|ALTER TABLE|DROP TABLE|"
  r"CREATE (?:TEMP(?:ORARY)? )?TABLE|GENERATE (?:EXPRESS )?STATISTICS ON|CALL)\s+([^\s(;]+)",
  caseSensitive: false,
);
final _reFrom = RegExp(r'''\bFROM\s+([A-Za-z_"][^\s,();]*)''', caseSensitive: false);

(String, bool) _tablaCorta(String t) {
  final limpio = t.replaceAll(_reComillas, "");
  final m = _reTemporal.firstMatch(limpio);
  return m != null ? ("${m.group(1)}${m.group(2)}", true) : (limpio, false);
}

ResumenSql resumirSql(String? comando) {
  final sql = (comando ?? "").replaceAll(_reEspacios, " ").trim();
  if (sql.isEmpty) return const ResumenSql();
  final externa = _reExterna.hasMatch(sql);
  final crear = _reCrearExterna.firstMatch(sql);
  if (crear != null) {
    final f = _reSelectFrom.firstMatch(sql);
    final (t, temporal) = _tablaCorta(f?.group(1) ?? crear.group(1)!);
    return ResumenSql(verbo: "Descarga", tabla: t, temporal: temporal, externa: externa, descarga: true);
  }
  final m = _reVerboTabla.firstMatch(sql);
  if (m != null) {
    final clave = m.group(1)!.split(" ").first.toUpperCase();
    final (t, temporal) = _tablaCorta(m.group(2)!);
    return ResumenSql(verbo: _verboTxt[clave] ?? m.group(1)!, tabla: t, temporal: temporal, externa: externa);
  }
  final primera = sql.split(" ").first.toUpperCase();
  final verbo = _verboTxt[primera] ?? primera;
  final f = _reFrom.firstMatch(sql);
  if (f != null && f.group(1)!.toUpperCase() != "EXTERNAL") {
    final (t, temporal) = _tablaCorta(f.group(1)!);
    return ResumenSql(verbo: verbo, tabla: t, temporal: temporal, externa: externa);
  }
  return ResumenSql(verbo: verbo, externa: externa);
}

/// «45 s», «12 min», «2 h 5 min» (como la web).
String duracionCorta(num? segundos) {
  final s = segundos == null || segundos < 0 ? 0 : segundos.round();
  if (s < 60) return "$s s";
  final m = s ~/ 60;
  if (m < 60) return "$m min";
  final r = m % 60;
  return "${m ~/ 60} h${r > 0 ? " $r min" : ""}";
}

/// Costo estimado abreviado: «8 M», «80 mil», «1,2 mil M».
String costoCorto(num n) {
  if (n >= 1e9) {
    final v = (n / 1e8).round() / 10;
    return "${v.toStringAsFixed(v == v.truncate() ? 0 : 1).replaceAll(".", ",")} mil M";
  }
  if (n >= 1e6) return "${formatearMiles((n / 1e6).round())} M";
  if (n >= 1e3) return "${formatearMiles((n / 1e3).round())} mil";
  return "${n.round()}";
}

/// Umbrales del monitor web para el costo estimado de Netezza.
const costoAlto = 100000;
const costoCritico = 1000000;

final _reZona = RegExp(r"([+-])(\d{2}):?(\d{2})?$");

/// Fecha del servidor ("2026-11-10 07:29:08", "2026-11-10 07:29:08 -04") como
/// instante. Con zona se respeta; sin zona es hora de Bolivia (-04:00), la de
/// los servidores de Nuevatel, asi el tiempo sale bien aunque el celular este
/// en otra zona horaria.
DateTime? fechaServidor(String? v) {
  final s = (v ?? "").trim();
  if (s.length < 19) return null;
  final base = s.substring(0, 19).replaceFirst(" ", "T");
  final m = _reZona.firstMatch(s.substring(19).trim());
  final zona = m != null ? "${m.group(1)}${m.group(2)}:${m.group(3) ?? "00"}" : "-04:00";
  return DateTime.tryParse("$base$zona");
}

/// Comienzo de la consulta en una linea (cuando no se reconoce la tabla).
String extractoSql(String? comando, {int largo = 80}) {
  final sql = (comando ?? "").replaceAll(_reEspacios, " ").trim();
  return sql.length <= largo ? sql : "${sql.substring(0, largo)}…";
}

/// Cuanto paso desde esa fecha («hace 2 h 5 min»), o null si no se entiende.
String? haceCuanto(String? fecha, {DateTime? ahora}) {
  final f = fechaServidor(fecha);
  if (f == null) return null;
  final seg = (ahora ?? DateTime.now()).difference(f).inSeconds;
  if (seg < 0) return null;
  return duracionCorta(seg);
}
