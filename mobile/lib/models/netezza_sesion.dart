import "../utils/formato.dart";

class NetezzaSesion {
  final String estado;
  final int sessionId;
  final String? qscState;
  final String? qsState;
  final num? qsEstcost;
  final num? qsEstdisk;
  final num? qsEstmem;
  final int? qsSnippets;
  final String? conntime;
  final String? ipaddr;
  final String? clientOsUsername;
  final String username;
  final String? dbname;
  final String? priority;
  final String? command;
  final num? qsResbytes;
  final num? qsResrows;

  NetezzaSesion({
    required this.estado,
    required this.sessionId,
    required this.username,
    this.qscState,
    this.qsState,
    this.qsEstcost,
    this.qsEstdisk,
    this.qsEstmem,
    this.qsSnippets,
    this.conntime,
    this.ipaddr,
    this.clientOsUsername,
    this.dbname,
    this.priority,
    this.command,
    this.qsResbytes,
    this.qsResrows,
  });

  factory NetezzaSesion.fromJson(Map<String, dynamic> json) {
    return NetezzaSesion(
      estado: (json["STATUS"] ?? "").toString(),
      sessionId: int.parse(json["SESSION_ID"].toString()),
      username: (json["USERNAME"] ?? "").toString(),
      qscState: json["QSC_STATE"]?.toString(),
      qsState: json["QS_STATE"]?.toString(),
      qsEstcost: leerNumero(json["QS_ESTCOST"]),
      qsEstdisk: leerNumero(json["QS_ESTDISK"]),
      qsEstmem: leerNumero(json["QS_ESTMEM"]),
      qsSnippets: leerNumero(json["QS_SNIPPETS"])?.toInt(),
      conntime: json["CONNTIME"]?.toString(),
      ipaddr: json["IPADDR"]?.toString(),
      clientOsUsername: json["CLIENT_OS_USERNAME"]?.toString(),
      dbname: json["DBNAME"]?.toString(),
      priority: json["PRIORITY"]?.toString(),
      command: json["COMMAND"]?.toString(),
      qsResbytes: leerNumero(json["QS_RESBYTES"]),
      qsResrows: leerNumero(json["QS_RESROWS"]),
    );
  }
}
