/// Un elemento monitoreado: un proceso (dataops_catalogo_procesos) o una
/// tabla (dataops_catalogo_tablas). Comparten nombre/fuente/estado/color, y
/// el monitor los lista con las mismas tarjetas; lo que cambia es el detalle
/// (horas de corrida vs. cantidad de registros y ultima carga).
class Control {
  final int id;
  final String tipo; // "PROCESO" | "TABLA"
  final String nombre;
  final String fuente;
  final String estado;
  final String color;
  final String? horaProgramada;
  final String? horaLog;
  final String? horaFin;
  final String? core;
  final String? ruta;
  final String? version;
  final int? cantidad; // solo tablas: registros
  final String? layer; // solo tablas: capa medallion (bronze/silver/gold)
  final String? ultimaFecha; // solo tablas: ultima carga
  final DateTime snapshotFecha;
  final DateTime snapshotTs;

  Control({
    required this.id,
    this.tipo = "PROCESO",
    required this.nombre,
    required this.fuente,
    required this.estado,
    required this.color,
    required this.snapshotFecha,
    required this.snapshotTs,
    this.horaProgramada,
    this.horaLog,
    this.horaFin,
    this.core,
    this.ruta,
    this.version,
    this.cantidad,
    this.layer,
    this.ultimaFecha,
  });

  factory Control.fromJson(Map<String, dynamic> json) {
    return Control(
      id: json["id"],
      nombre: json["nombre"],
      fuente: json["fuente"],
      estado: json["estado"],
      color: json["color"],
      horaProgramada: json["hora_programada"],
      horaLog: json["hora_log"],
      horaFin: json["hora_fin"],
      core: json["core"],
      ruta: json["ruta"],
      version: json["version"],
      snapshotFecha: DateTime.parse(json["snapshot_fecha"]),
      snapshotTs: DateTime.parse(json["snapshot_ts"]),
    );
  }

  factory Control.fromTablaJson(Map<String, dynamic> json) {
    return Control(
      id: json["id"],
      tipo: "TABLA",
      nombre: json["nombre"],
      fuente: json["fuente"],
      estado: json["estado"],
      color: json["color"],
      horaProgramada: json["hora_programada"],
      cantidad: json["cantidad"],
      layer: json["layer"],
      ultimaFecha: json["ultima_fecha"],
      // 'SI' en las tablas core (modal «Tablas core» de la web), como en los procesos.
      core: json["core"],
      snapshotFecha: DateTime.parse(json["snapshot_fecha"]),
      snapshotTs: DateTime.parse(json["snapshot_ts"]),
    );
  }

  bool get esTabla => tipo == "TABLA";

  /// El backend reclasifica un DEMORADO (ya paso su hora_fin) como color
  /// "red" para tratarlo como falla real -nunca llega un control con color
  /// "orange" crudo-, asi que hay que distinguirlo por estado para no
  /// mostrarlo visualmente igual que un error duro.
  bool get esDemorado => color == "red" && estado.toUpperCase() == "DEMORADO";

  /// Gris "EN TIEMPO": todavia no le toca correr (lo que el monitor web de
  /// procesos llama "En proceso"), distinto de un gris sin ejecucion.
  bool get esEnTiempo => color == "gray" && estado.trim().toUpperCase() == "EN TIEMPO";

  /// Categoria con la misma semantica que los contadores del monitor web:
  /// red (error), orange (demorado), blue (actualizando/corriendo), green
  /// (OK), tiempo (en proceso) y gray (sin ejecucion / pausado sin corrida).
  String get categoria {
    if (esDemorado) return "orange";
    if (esEnTiempo) return "tiempo";
    switch (color) {
      case "red":
      case "orange":
      case "blue":
      case "green":
        return color;
      default:
        return "gray";
    }
  }

  /// Proceso de DataStage/Pentaho que hoy todavia no corrio: demorado, en
  /// tiempo (aun no le toca) o sin ejecucion; en el catalogo no tienen hora de
  /// inicio. Los que si corrieron terminaron OK, fallaron o estan corriendo.
  /// Airflow no entra: un DAG semanal o pausado tiene su ultima corrida en
  /// otro dia sin que falte nada.
  bool get noCorrio {
    if (esTabla || fuente.trim().toUpperCase() == "AIRFLOW") return false;
    final c = categoria;
    return c == "orange" || c == "tiempo" || c == "gray";
  }

  /// Los que no corrieron van arriba: primero los demorados y despues por
  /// hora de fin esperada. El resto queda en el orden en que venia.
  static List<Control> noCorrieronPrimero(List<Control> lista) {
    final pendientes = lista.where((c) => c.noCorrio).toList()
      ..sort((a, b) {
        final da = a.categoria == "orange" ? 0 : 1;
        final db = b.categoria == "orange" ? 0 : 1;
        if (da != db) return da - db;
        final fa = (a.horaFin ?? "").trim();
        final fb = (b.horaFin ?? "").trim();
        if (fa.isEmpty != fb.isEmpty) return fa.isEmpty ? 1 : -1;
        final porHora = fa.compareTo(fb);
        return porHora != 0 ? porHora : a.nombre.compareTo(b.nombre);
      });
    if (pendientes.isEmpty) return lista;
    return [...pendientes, ...lista.where((c) => !c.noCorrio)];
  }

  /// Cantidad de registros con separador de miles ("1.234.567").
  String? get cantidadFormateada {
    final n = cantidad;
    if (n == null) return null;
    final digitos = n.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      final restantes = digitos.length - i;
      buffer.write(digitos[i]);
      if (restantes > 1 && restantes % 3 == 1) buffer.write(".");
    }
    return n < 0 ? "-$buffer" : buffer.toString();
  }
}
