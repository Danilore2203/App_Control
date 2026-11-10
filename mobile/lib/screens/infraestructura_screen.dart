import "dart:async";

import "package:flutter/material.dart";

import "../models/netezza_bloqueos.dart";
import "../models/netezza_sesion.dart";
import "../models/postgres_sesion.dart";
import "../services/infra_service.dart";
import "../services/sesion_actual.dart";
import "../theme.dart";
import "../utils/sql_resumen.dart";
import "../widgets/bloqueos_netezza.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/infra_comun.dart";
import "../widgets/pestanas.dart";
import "../widgets/tarjeta_sesion_netezza.dart";
import "../widgets/tarjeta_sesion_postgres.dart";
import "../widgets/titulo_seccion.dart";

/// Version con AppBar propio, para abrir desde el drawer o el banner de
/// bloqueos Postgres. El contenido vive en [InfraestructuraContenido].
class InfraestructuraScreen extends StatelessWidget {
  const InfraestructuraScreen({super.key, this.escenaInicial = 0});

  /// 0 Netezza, 1 Bloqueos, 2 PG DEV, 3 PG PROD.
  final int escenaInicial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Infraestructura")),
      body: InfraestructuraContenido(escenaInicial: escenaInicial),
    );
  }
}

/// Sesiones de Netezza y PostgreSQL DEV/PROD, y los bloqueos de Netezza,
/// como el monitor web. Cada consulta es un comando que OP_PROD ejecuta desde
/// adentro de la red. Abortar, matar y cancelar: solo administradores.
class InfraestructuraContenido extends StatefulWidget {
  const InfraestructuraContenido({super.key, this.escenaInicial = 0});

  final int escenaInicial;

  @override
  State<InfraestructuraContenido> createState() => _InfraestructuraContenidoState();
}

typedef _DatosNz = ({List<NetezzaSesion> activas, List<NetezzaSesion> idle});
typedef _DatosPg = ({List<PostgresSesion> filas, int total, int activas});

class _InfraestructuraContenidoState extends State<InfraestructuraContenido> {
  static const _escenas = ["Netezza", "Bloqueos", "PG DEV", "PG PROD"];
  static const _cadaBloqueos = Duration(seconds: 30);

  final _infra = InfraService();
  late int _escena = widget.escenaInicial.clamp(0, _escenas.length - 1);

  late Future<_DatosNz> _nzFuture;
  late Future<_DatosPg> _devFuture;
  late Future<_DatosPg> _prodFuture;
  bool _soloActivasDev = true;
  bool _soloActivasProd = true;
  bool _verIdle = false;

  BloqueosNetezza? _bloqueos;
  Object? _errorBloqueos;
  bool _cargandoBloqueos = false;
  Timer? _relojBloqueos;

  // Ultimos datos de PG para el contador de las pestañas.
  int _bloqueadasDev = 0;
  int _bloqueadasProd = 0;

  bool get _esAdmin => SesionActual.esAdmin;

  @override
  void initState() {
    super.initState();
    _nzFuture = _infra.obtenerNetezzaSesiones();
    _devFuture = _pg(prod: false);
    _prodFuture = _pg(prod: true);
    _cargarBloqueos();
    // La espera de una sesion se mide entre lecturas: mientras se mira la
    // pestaña se vuelve a revisar sola, como la web.
    _relojBloqueos = Timer.periodic(_cadaBloqueos, (_) {
      if (mounted && _escena == 1) _cargarBloqueos();
    });
  }

  @override
  void dispose() {
    _relojBloqueos?.cancel();
    super.dispose();
  }

  Future<_DatosPg> _pg({required bool prod}) async {
    final d = prod
        ? await _infra.obtenerPostgresProd(soloActivas: _soloActivasProd)
        : await _infra.obtenerPostgresDev(soloActivas: _soloActivasDev);
    final bloqueadas = d.filas.where((s) => s.estaBloqueada).length;
    if (mounted) {
      setState(() => prod ? _bloqueadasProd = bloqueadas : _bloqueadasDev = bloqueadas);
    }
    return d;
  }

  Future<void> _cargarBloqueos() async {
    if (_cargandoBloqueos) return;
    setState(() => _cargandoBloqueos = true);
    try {
      final b = await _infra.obtenerBloqueosNetezza();
      if (!mounted) return;
      setState(() {
        _bloqueos = b;
        _errorBloqueos = null;
      });
    } catch (e) {
      if (mounted) setState(() => _errorBloqueos = e);
    } finally {
      if (mounted) setState(() => _cargandoBloqueos = false);
    }
  }

  void _recargarNetezza() {
    setState(() => _nzFuture = _infra.obtenerNetezzaSesiones());
    _cargarBloqueos();
  }

  // ---- Acciones (solo administradores) ----

  Future<void> _abortar(int sessionId) async {
    final ok = await confirmarAccion(
      context,
      titulo: "¿Abortar la transacción?",
      mensaje: "Se deshace la transacción en curso de la sesión $sessionId y suelta sus bloqueos. La sesión sigue conectada.",
      boton: "Abortar",
      tarea: () => _infra.abortarTransaccionNetezza(sessionId),
      exito: "Transacción de la sesión $sessionId abortada.",
    );
    if (ok && mounted) _recargarNetezza();
  }

  Future<void> _matar(int sessionId) async {
    final ok = await confirmarAccion(
      context,
      titulo: "¿Matar la sesión?",
      mensaje: "Se desconecta la sesión $sessionId (DROP SESSION) y se deshace lo que no confirmó. "
          "El programa que la abrió verá el error.",
      boton: "Matar",
      tarea: () => _infra.matarSesionNetezza(sessionId),
      exito: "Sesión $sessionId terminada.",
    );
    if (ok && mounted) _recargarNetezza();
  }

  Future<void> _cancelarPg({required bool prod, required int pid}) async {
    final ok = await confirmarAccion(
      context,
      titulo: "¿Cancelar la consulta?",
      mensaje: "Se cancela la consulta en curso del PID $pid en PostgreSQL ${prod ? "PROD" : "DEV"}.",
      boton: "Cancelar consulta",
      tarea: () => prod ? _infra.cancelarSesionPostgresProd(pid) : _infra.cancelarSesionPostgresDev(pid),
      exito: "Cancelación enviada al PID $pid.",
    );
    if (ok && mounted) {
      setState(() => prod ? _prodFuture = _pg(prod: true) : _devFuture = _pg(prod: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: PestanasSimples(
            seleccionada: _escena,
            opciones: _escenas,
            alertas: [0, _bloqueos?.alertas ?? 0, _bloqueadasDev, _bloqueadasProd],
            onCambiar: (i) {
              setState(() => _escena = i);
              if (i == 1) _cargarBloqueos();
            },
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: switch (_escena) {
            0 => _vistaNetezza(),
            1 => _vistaBloqueos(),
            2 => _vistaPostgres(prod: false),
            _ => _vistaPostgres(prod: true),
          },
        ),
      ],
    );
  }

  Widget _error(Object error, VoidCallback onReintentar) {
    return EstadoVacio(
      icono: Icons.dns_outlined,
      mensaje: "No se pudo consultar el monitor",
      detalle: error.toString().replaceFirst("Exception: ", ""),
      colorIcono: Theme.of(context).colorScheme.error,
      onReintentar: onReintentar,
    );
  }

  // ---- Netezza ----

  Widget _vistaNetezza() {
    return FutureBuilder<_DatosNz>(
      future: _nzFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _error(snapshot.error!, _recargarNetezza);
        final colorScheme = Theme.of(context).colorScheme;
        final activas = [...snapshot.data!.activas]
          ..sort((a, b) => (b.qsEstcost ?? 0).compareTo(a.qsEstcost ?? 0));
        final idle = snapshot.data!.idle;
        final pesadas = activas.where((s) => (s.qsEstcost ?? 0) >= costoAlto).length;
        final b = _bloqueos;

        return RefreshIndicator(
          onRefresh: () async {
            _recargarNetezza();
            await _nzFuture;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              FilaIndicadores([
                ("Activas", "${activas.length}", StatusColors.info, Icons.bolt_rounded),
                ("Idle", "${idle.length}", null, Icons.pause_circle_outline_rounded),
                ("Pesadas", "$pesadas", pesadas > 0 ? StatusColors.advertencia : null, Icons.speed_rounded),
              ]),
              if (b != null && b.alertas > 0) ...[
                const SizedBox(height: 12),
                AvisoTocable(
                  texto: _textoAvisoBloqueos(b),
                  icono: Icons.lock_outline_rounded,
                  color: StatusColors.critico,
                  accion: "Ver",
                  onTap: () {
                    setState(() => _escena = 1);
                    _cargarBloqueos();
                  },
                ),
              ],
              const SizedBox(height: 16),
              TituloSeccion("Sesiones activas", accion: _contador(activas.length)),
              const SizedBox(height: 8),
              if (activas.isEmpty)
                EstadoVacio(
                  icono: Icons.check_circle_outline,
                  mensaje: "Ninguna sesión activa en Netezza",
                  colorIcono: colorScheme.onSurfaceVariant,
                )
              else
                for (final s in activas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaSesionNetezza(
                      sesion: s,
                      onAbortar: _esAdmin ? () => _abortar(s.sessionId) : null,
                      onMatar: _esAdmin ? () => _matar(s.sessionId) : null,
                    ),
                  ),
              if (idle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _verIdle = !_verIdle),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: TituloSeccion("Idle", accion: _contador(idle.length))),
                          const SizedBox(width: 6),
                          Icon(_verIdle ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_verIdle)
                  for (final s in idle)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TarjetaSesionNetezza(
                        sesion: s,
                        compacta: true,
                        onMatar: _esAdmin ? () => _matar(s.sessionId) : null,
                      ),
                    ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _textoAvisoBloqueos(BloqueosNetezza b) {
    final partes = <String>[
      if (b.cuenta("esperando") > 0) "${b.cuenta("esperando")} esperando",
      if (b.cuenta("bloqueadoras") > 0) "${b.cuenta("bloqueadoras")} las frenan",
      if (b.cuenta("sin_avance") > 0) "${b.cuenta("sin_avance")} sin avanzar",
      if (b.cuenta("en_cola") > 0) "${b.cuenta("en_cola")} en cola",
    ];
    return "Netezza: ${partes.join(" · ")}.";
  }

  Widget _contador(int n) => Text(
        "$n",
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      );

  // ---- Bloqueos ----

  Widget _vistaBloqueos() {
    final b = _bloqueos;
    if (b == null) {
      if (_errorBloqueos != null) return _error(_errorBloqueos!, _cargarBloqueos);
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        if (_errorBloqueos != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: MensajeInline(
              "No se pudo actualizar: ${_errorBloqueos.toString().replaceFirst("Exception: ", "")}",
              color: StatusColors.advertencia,
              icono: Icons.sync_problem_rounded,
            ),
          ),
        Expanded(
          child: BloqueosNetezzaVista(
            datos: b,
            actualizando: _cargandoBloqueos,
            onRefrescar: _cargarBloqueos,
            onAbortar: _esAdmin ? (s) => _abortar(s.sessionId) : null,
            onMatar: _esAdmin ? (s) => _matar(s.sessionId) : null,
          ),
        ),
      ],
    );
  }

  // ---- PostgreSQL ----

  Widget _vistaPostgres({required bool prod}) {
    final future = prod ? _prodFuture : _devFuture;
    final soloActivas = prod ? _soloActivasProd : _soloActivasDev;
    void recargar() => setState(() => prod ? _prodFuture = _pg(prod: true) : _devFuture = _pg(prod: false));

    return FutureBuilder<_DatosPg>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _error(snapshot.error!, recargar);
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final datos = snapshot.data!;

        // Quien bloquea a quien: cuantas sesiones de la lista espera cada PID.
        final bloqueaA = <int, int>{};
        for (final s in datos.filas) {
          for (final p in s.pidsQueLaBloquean) {
            final pid = int.tryParse(p);
            if (pid != null) bloqueaA[pid] = (bloqueaA[pid] ?? 0) + 1;
          }
        }
        final bloqueadas = datos.filas.where((s) => s.estaBloqueada).length;
        int peso(PostgresSesion s) => (bloqueaA[s.pid] ?? 0) * 10 + (s.estaBloqueada ? 5 : 0) + (s.estado == "active" ? 1 : 0);
        final filas = [...datos.filas]..sort((a, b) => peso(b).compareTo(peso(a)));
        final culpables = bloqueaA.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        return RefreshIndicator(
          onRefresh: () async {
            recargar();
            await (prod ? _prodFuture : _devFuture);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              FilaIndicadores([
                ("Total", "${datos.total}", null, Icons.lan_outlined),
                ("Activas", "${datos.activas}", StatusColors.info, Icons.bolt_rounded),
                ("Bloqueadas", "$bloqueadas", bloqueadas > 0 ? StatusColors.critico : null, Icons.lock_clock_outlined),
              ]),
              if (culpables.isNotEmpty) ...[
                const SizedBox(height: 12),
                AvisoTocable(
                  icono: Icons.block_rounded,
                  color: StatusColors.critico,
                  texto: culpables
                      .take(3)
                      .map((e) => "PID ${e.key} bloquea a ${e.value} ${e.value == 1 ? "sesión" : "sesiones"}")
                      .join(" · "),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: TituloSeccion("Sesiones · ${filas.length}")),
                  Text(
                    "Solo activas",
                    style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: soloActivas,
                      onChanged: (valor) => setState(() {
                        if (prod) {
                          _soloActivasProd = valor;
                          _prodFuture = _pg(prod: true);
                        } else {
                          _soloActivasDev = valor;
                          _devFuture = _pg(prod: false);
                        }
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (filas.isEmpty)
                EstadoVacio(
                  icono: Icons.check_circle_outline,
                  mensaje: "Sin sesiones para mostrar",
                  colorIcono: colorScheme.onSurfaceVariant,
                )
              else
                for (final s in filas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaSesionPostgres(
                      sesion: s,
                      bloqueaA: bloqueaA[s.pid] ?? 0,
                      onCancelar: _esAdmin ? () => _cancelarPg(prod: prod, pid: s.pid) : null,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
