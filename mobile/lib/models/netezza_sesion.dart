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
      qsEstcost: json["QS_ESTCOST"] as num?,
      qsEstdisk: json["QS_ESTDISK"] as num?,
      qsEstmem: json["QS_ESTMEM"] as num?,
      qsSnippets: (json["QS_SNIPPETS"] as num?)?.toInt(),
      conntime: json["CONNTIME"]?.toString(),
      ipaddr: json["IPADDR"]?.toString(),
      clientOsUsername: json["CLIENT_OS_USERNAME"]?.toString(),
      dbname: json["DBNAME"]?.toString(),
      priority: json["PRIORITY"]?.toString(),
      command: json["COMMAND"]?.toString(),
      qsResbytes: json["QS_RESBYTES"] as num?,
      qsResrows: json["QS_RESROWS"] as num?,
    );
  }
}
