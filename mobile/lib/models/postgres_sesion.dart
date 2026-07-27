class PostgresSesion {
  final int pid;
  final String? datname;
  final String? username;
  final String? applicationName;
  final String? clientAddr;
  final String? backendStart;
  final String? xactStart;
  final String? estado;
  final String? waitEvent;
  final String blockingPids;
  final String? queryText;

  PostgresSesion({
    required this.pid,
    this.datname,
    this.username,
    this.applicationName,
    this.clientAddr,
    this.backendStart,
    this.xactStart,
    this.estado,
    this.waitEvent,
    this.blockingPids = "",
    this.queryText,
  });

  bool get estaBloqueada => blockingPids.trim().isNotEmpty;

  List<String> get pidsQueLaBloquean =>
      blockingPids.split(",").map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

  factory PostgresSesion.fromJson(Map<String, dynamic> json) {
    return PostgresSesion(
      pid: int.parse(json["PID"].toString()),
      datname: json["DATNAME"]?.toString(),
      username: json["USERNAME"]?.toString(),
      applicationName: json["APPLICATION_NAME"]?.toString(),
      clientAddr: json["CLIENT_ADDR"]?.toString(),
      backendStart: json["BACKEND_START"]?.toString(),
      xactStart: json["XACT_START"]?.toString(),
      estado: json["STATE"]?.toString(),
      waitEvent: json["WAIT_EVENT"]?.toString(),
      blockingPids: (json["BLOCKING_PIDS"] ?? "").toString(),
      queryText: json["QUERY_TEXT"]?.toString(),
    );
  }
}
