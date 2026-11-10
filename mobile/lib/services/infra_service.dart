import "../models/netezza_bloqueos.dart";
import "../models/netezza_sesion.dart";
import "../models/postgres_sesion.dart";
import "comandos_service.dart";

/// Sesiones de Netezza / PostgreSQL DEV / PostgreSQL PROD, igual que el
/// monitor web de OP. El servidor OP esta en la red interna de Nuevatel y
/// el celular puede estar en cualquier lado, asi que cada consulta es un
/// comando que OP_PROD ejecuta desde adentro y nos devuelve (ver
/// ComandosService): tarda unos segundos en vez de ser instantanea.
class InfraService {
  final _comandos = ComandosService();

  // ---- Netezza ----

  Future<({List<NetezzaSesion> activas, List<NetezzaSesion> idle})>
      obtenerNetezzaSesiones() async {
    final r = await _comandos.ejecutar("infra.netezza.sesiones");
    final activas =
        ((r.resultado["active"] as List?) ?? const []).map((j) => NetezzaSesion.fromJson(j)).toList();
    final idle =
        ((r.resultado["idle"] as List?) ?? const []).map((j) => NetezzaSesion.fromJson(j)).toList();
    return (activas: activas, idle: idle);
  }

  Future<void> abortarTransaccionNetezza(int sessionId) =>
      _comandos.ejecutar("infra.netezza.abort_txn", payload: {"session_id": sessionId});

  /// DROP SESSION: desconecta al cliente (abortar solo deshace la transaccion).
  Future<void> matarSesionNetezza(int sessionId) =>
      _comandos.ejecutar("infra.netezza.kill", payload: {"session_id": sessionId});

  /// Quien frena a quien, transacciones abiertas y consultas trabadas (como la web).
  Future<BloqueosNetezza> obtenerBloqueosNetezza() async {
    final r = await _comandos.ejecutar("infra.netezza.bloqueos");
    return BloqueosNetezza.fromJson(r.resultado);
  }

  // ---- PostgreSQL (DEV y PROD, mismo formato) ----

  Future<({List<PostgresSesion> filas, int total, int activas})> _postgresData(
      String entorno, bool soloActivas) async {
    final r = await _comandos.ejecutar(
      "infra.postgres.sesiones",
      payload: {"entorno": entorno, "solo_activas": soloActivas},
    );
    final filas =
        ((r.resultado["rows"] as List?) ?? const []).map((j) => PostgresSesion.fromJson(j)).toList();
    final counts = (r.resultado["counts"] as Map<String, dynamic>?) ?? const {};
    return (
      filas: filas,
      total: (counts["total"] as num?)?.toInt() ?? filas.length,
      activas: (counts["active"] as num?)?.toInt() ?? 0,
    );
  }

  Future<({List<PostgresSesion> filas, int total, int activas})>
      obtenerPostgresDev({bool soloActivas = true}) => _postgresData("dev", soloActivas);

  Future<({List<PostgresSesion> filas, int total, int activas})>
      obtenerPostgresProd({bool soloActivas = true}) => _postgresData("prod", soloActivas);

  Future<void> cancelarSesionPostgresDev(int pid) =>
      _comandos.ejecutar("infra.postgres.cancel", payload: {"entorno": "dev", "pid": pid});

  Future<void> cancelarSesionPostgresProd(int pid) =>
      _comandos.ejecutar("infra.postgres.cancel", payload: {"entorno": "prod", "pid": pid});

  /// Conteo de sesiones bloqueadas en PROD (para el banner del monitor).
  /// Es una consulta completa de sesiones activas, asi que se llama con
  /// poca frecuencia (ver dashboard).
  Future<({int total, int activas, int bloqueadas})> postgresProdAlertPoll() async {
    final datos = await obtenerPostgresProd(soloActivas: true);
    return (
      total: datos.total,
      activas: datos.activas,
      bloqueadas: datos.filas.where((s) => s.estaBloqueada).length,
    );
  }
}
