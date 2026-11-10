import "../utils/formato.dart";
import "../utils/sql_resumen.dart";

/// Bloqueos de Netezza como los arma OP_PROD (modules/netezza/bloqueos.py)
/// para la seccion «Bloqueos y consultas trabadas» del monitor web. Netezza
/// no deja leer su tabla de bloqueos al usuario del monitor: se deduce de las
/// sesiones y del historial de consultas.

class TablaAcceso {
  final String tabla;
  final String acceso; // exclusivo | escritura | inserción | lectura

  const TablaAcceso(this.tabla, this.acceso);

  String get tablaCorta => tabla.split("..").last;
}

/// Por que una sesion espera a otra: la otra retiene la tabla con un acceso
/// que choca con el que esta pide.
class ChoqueTabla {
  final String tabla;
  final String retiene;
  final String pide;

  const ChoqueTabla(this.tabla, this.retiene, this.pide);

  String get tablaCorta => tabla.split("..").last;
}

class SesionBloqueo {
  final int sessionId;
  final String? status;
  final String? username;
  final String? dbname;
  final String? ipaddr;
  final String? clientOsUsername;
  final String? conntime;
  final String? command;
  final num? costo;
  final String? dagId;
  final String? taskId;

  /// corriendo | esperando | tx-idle (en bloqueos).
  final String estado;
  final int segundos;
  final int segundosMedidos;
  final List<TablaAcceso> tablas;
  final List<ChoqueTabla> choque;
  final bool tambienEspera;
  final List<SesionBloqueo> posibles;

  /// Consultas trabadas: sin_avance | en_cola | cliente | larga.
  final String? tipo;
  final int quietaS;
  final int correS;
  final int pasos;
  final int pasoActual;

  const SesionBloqueo({
    required this.sessionId,
    this.status,
    this.username,
    this.dbname,
    this.ipaddr,
    this.clientOsUsername,
    this.conntime,
    this.command,
    this.costo,
    this.dagId,
    this.taskId,
    this.estado = "",
    this.segundos = 0,
    this.segundosMedidos = 0,
    this.tablas = const [],
    this.choque = const [],
    this.tambienEspera = false,
    this.posibles = const [],
    this.tipo,
    this.quietaS = 0,
    this.correS = 0,
    this.pasos = 0,
    this.pasoActual = 0,
  });

  factory SesionBloqueo.fromJson(Map<String, dynamic> j) {
    int entero(Object? v) => leerNumero(v)?.toInt() ?? 0;
    String? texto(Object? v) {
      final s = v?.toString().trim() ?? "";
      return s.isEmpty ? null : s;
    }

    List<Map<String, dynamic>> lista(Object? v) =>
        ((v as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

    return SesionBloqueo(
      sessionId: entero(j["SESSION_ID"]),
      status: texto(j["STATUS"]),
      username: texto(j["USERNAME"]),
      dbname: texto(j["DBNAME"]),
      ipaddr: texto(j["IPADDR"]),
      clientOsUsername: texto(j["CLIENT_OS_USERNAME"]),
      conntime: texto(j["CONNTIME"]),
      command: texto(j["COMMAND"]),
      costo: leerNumero(j["QS_ESTCOST"]),
      dagId: texto(j["dag_id"]),
      taskId: texto(j["task_id"]),
      estado: (j["estado"] ?? "").toString(),
      segundos: entero(j["segundos"]),
      segundosMedidos: entero(j["segundos_medidos"]),
      tablas: lista(j["tablas"]).map((t) => TablaAcceso((t["tabla"] ?? "").toString(), (t["acceso"] ?? "").toString())).toList(),
      choque: lista(j["choque"])
          .map((c) => ChoqueTabla((c["tabla"] ?? "").toString(), (c["retiene"] ?? "").toString(), (c["pide"] ?? "").toString()))
          .toList(),
      tambienEspera: j["tambien_espera"] == true,
      posibles: lista(j["posibles"]).map(SesionBloqueo.fromJson).toList(),
      tipo: texto(j["tipo"]),
      quietaS: entero(j["quieta_s"]),
      correS: entero(j["corre_s"]),
      pasos: entero(j["pasos"]),
      pasoActual: entero(j["paso_actual"]),
    );
  }

  /// dsadm es el usuario de DataStage en el cliente.
  bool get esDataStage => (clientOsUsername ?? "").toLowerCase() == "dsadm";

  ResumenSql get resumen => resumirSql(command);

  /// Usuario del sistema operativo que vale la pena mostrar («default» no dice nada).
  String? get usuarioSo {
    final os = (clientOsUsername ?? "").trim();
    if (os.isEmpty || os.toLowerCase() == "default" || esDataStage) return null;
    return os;
  }
}

class GrupoBloqueo {
  final SesionBloqueo bloqueadora;
  final List<SesionBloqueo> esperan;

  const GrupoBloqueo(this.bloqueadora, this.esperan);
}

class BloqueosNetezza {
  final String? ahora;
  final List<GrupoBloqueo> bloqueos;
  final List<SesionBloqueo> esperandoSinCausa;
  final List<SesionBloqueo> txAbiertas;
  final List<SesionBloqueo> trabadas;
  final List<SesionBloqueo> ocupan;
  final Map<String, int> resumen;
  final int esperaMinS;
  final int largaMinS;
  final int sinAvanceS;

  const BloqueosNetezza({
    this.ahora,
    this.bloqueos = const [],
    this.esperandoSinCausa = const [],
    this.txAbiertas = const [],
    this.trabadas = const [],
    this.ocupan = const [],
    this.resumen = const {},
    this.esperaMinS = 30,
    this.largaMinS = 600,
    this.sinAvanceS = 300,
  });

  factory BloqueosNetezza.fromJson(Map<String, dynamic> j) {
    List<SesionBloqueo> sesiones(Object? v) =>
        ((v as List?) ?? const []).whereType<Map>().map((m) => SesionBloqueo.fromJson(Map<String, dynamic>.from(m))).toList();
    final umbrales = (j["umbrales"] as Map?) ?? const {};
    return BloqueosNetezza(
      ahora: j["ahora"]?.toString(),
      bloqueos: ((j["bloqueos"] as List?) ?? const []).whereType<Map>().map((g) {
        final m = Map<String, dynamic>.from(g);
        return GrupoBloqueo(
          SesionBloqueo.fromJson(Map<String, dynamic>.from((m["bloqueadora"] as Map?) ?? const {})),
          sesiones(m["esperan"]),
        );
      }).toList(),
      esperandoSinCausa: sesiones(j["esperando_sin_causa"]),
      txAbiertas: sesiones(j["tx_abiertas"]),
      trabadas: sesiones(j["trabadas"]),
      ocupan: sesiones(j["ocupan"]),
      resumen: {
        for (final e in ((j["resumen"] as Map?) ?? const {}).entries) e.key.toString(): leerNumero(e.value)?.toInt() ?? 0,
      },
      esperaMinS: leerNumero(j["espera_min_s"])?.toInt() ?? 30,
      largaMinS: leerNumero(umbrales["larga_min_s"])?.toInt() ?? 600,
      sinAvanceS: leerNumero(umbrales["sin_avance_s"])?.toInt() ?? 300,
    );
  }

  int cuenta(String clave) => resumen[clave] ?? 0;

  List<SesionBloqueo> get noAvanzan => trabadas.where((t) => t.tipo == "sin_avance" || t.tipo == "cliente").toList();
  List<SesionBloqueo> get enCola => trabadas.where((t) => t.tipo == "en_cola").toList();
  List<SesionBloqueo> get largas => trabadas.where((t) => t.tipo == "larga").toList();

  /// Lo que pide atencion (para el contador de la pestaña): esperas, culpables,
  /// consultas que no avanzan y en cola. Las largas que avanzan y las
  /// transacciones abiertas solas son informativas.
  int get alertas => cuenta("esperando") + cuenta("sin_avance") + cuenta("en_cola");

  bool get todoEnOrden => resumen.values.every((n) => n == 0);
}

/// Sesiones con la misma consulta (cargas de DataStage en paralelo) van en
/// una sola fila, como en la web.
List<List<SesionBloqueo>> agruparTrabadas(List<SesionBloqueo> lista) {
  final grupos = <String, List<SesionBloqueo>>{};
  for (final t in lista) {
    final r = t.resumen;
    final clave = [t.tipo, t.username, t.ipaddr, r.verbo, r.tabla].join("|");
    grupos.putIfAbsent(clave, () => []).add(t);
  }
  int orden(SesionBloqueo t) => switch (t.tipo) {
        "sin_avance" => t.quietaS,
        "larga" => t.correS,
        _ => t.segundos,
      };
  for (final g in grupos.values) {
    g.sort((a, b) => orden(b).compareTo(orden(a)));
  }
  return grupos.values.toList();
}
