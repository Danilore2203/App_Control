import "package:flutter/material.dart";

import "../models/netezza_sesion.dart";
import "../models/postgres_sesion.dart";
import "../services/infra_service.dart";
import "../theme.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/tarjeta_sesion_netezza.dart";
import "../widgets/tarjeta_sesion_postgres.dart";

/// Version con AppBar propio, para abrir desde el drawer o el banner de
/// bloqueos Postgres (ya no es una pestana del menu inferior). El contenido
/// vive en [InfraestructuraContenido] para poder reusarlo en otro lado.
class InfraestructuraScreen extends StatelessWidget {
  const InfraestructuraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text("INFRAESTRUCTURA",
            style:
                AppTextStyles.tech(color: colorScheme.onSurface, fontSize: 14)),
      ),
      body: const InfraestructuraContenido(),
    );
  }
}

/// Modulo de infraestructura: sesiones reales de Netezza y PostgreSQL
/// DEV/PROD, hablando directo con el monitor OP existente (mismo AD).
class InfraestructuraContenido extends StatefulWidget {
  const InfraestructuraContenido({super.key});

  @override
  State<InfraestructuraContenido> createState() => _InfraestructuraContenidoState();
}

class _InfraestructuraContenidoState extends State<InfraestructuraContenido> {
  final _infraService = InfraService();
  int _escena = 0;

  late Future<({List<NetezzaSesion> activas, List<NetezzaSesion> idle})>
      _netezzaFuture;
  late Future<({List<PostgresSesion> filas, int total, int activas})>
      _devFuture;
  late Future<({List<PostgresSesion> filas, int total, int activas})>
      _prodFuture;

  bool _soloActivasDev = true;
  bool _soloActivasProd = true;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  void _cargarTodo() {
    _netezzaFuture = _infraService.obtenerNetezzaSesiones();
    _devFuture = _infraService.obtenerPostgresDev(soloActivas: _soloActivasDev);
    _prodFuture =
        _infraService.obtenerPostgresProd(soloActivas: _soloActivasProd);
  }

  Future<bool> _confirmar(String titulo, String mensaje) async {
    final colorScheme = Theme.of(context).colorScheme;
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancelar")),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: StatusColors.critico),
            child: const Text("Sí, continuar"),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  void _mostrarResultado(String mensaje, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? StatusColors.critico : StatusColors.exitoso,
      ),
    );
  }

  Future<void> _abortarNetezza(int sessionId) async {
    final ok = await _confirmar(
      "Abortar transacción",
      "¿Abortar la transacción activa de la sesión Netezza #$sessionId? Esto no cierra la sesión, solo su transacción en curso.",
    );
    if (!ok) return;
    try {
      await _infraService.abortarTransaccionNetezza(sessionId);
      _mostrarResultado("Transacción abortada.");
      setState(() => _netezzaFuture = _infraService.obtenerNetezzaSesiones());
    } catch (e) {
      _mostrarResultado(e.toString().replaceFirst("Exception: ", ""),
          esError: true);
    }
  }

  Future<void> _cancelarPostgres(
      {required bool esProd, required int pid}) async {
    final ok = await _confirmar(
      "Cancelar sesión",
      "¿Cancelar la consulta en curso del PID $pid en PostgreSQL ${esProd ? 'PROD' : 'DEV'}?",
    );
    if (!ok) return;
    try {
      if (esProd) {
        await _infraService.cancelarSesionPostgresProd(pid);
      } else {
        await _infraService.cancelarSesionPostgresDev(pid);
      }
      _mostrarResultado("Cancelación enviada.");
      setState(() {
        if (esProd) {
          _prodFuture =
              _infraService.obtenerPostgresProd(soloActivas: _soloActivasProd);
        } else {
          _devFuture =
              _infraService.obtenerPostgresDev(soloActivas: _soloActivasDev);
        }
      });
    } catch (e) {
      _mostrarResultado(e.toString().replaceFirst("Exception: ", ""),
          esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            "ESCENAS DE CONTROL",
            style: AppTextStyles.tech(
                color: colorScheme.onSurfaceVariant, fontSize: 10),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _PillEscena(
                  texto: "Netezza",
                  seleccionado: _escena == 0,
                  onTap: () => setState(() => _escena = 0)),
              const SizedBox(width: 8),
              _PillEscena(
                  texto: "Postgres DEV",
                  seleccionado: _escena == 1,
                  onTap: () => setState(() => _escena = 1)),
              const SizedBox(width: 8),
              _PillEscena(
                  texto: "Postgres PROD",
                  seleccionado: _escena == 2,
                  onTap: () => setState(() => _escena = 2)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_escena) {
            0 => _vistaNetezza(colorScheme),
            1 => _vistaPostgres(colorScheme, esProd: false),
            _ => _vistaPostgres(colorScheme, esProd: true),
          },
        ),
      ],
    );
  }

  Widget _errorInfra(Object error, VoidCallback onReintentar) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EstadoVacio(
              icono: Icons.dns_outlined,
              mensaje: error.toString().replaceFirst("Exception: ", ""),
              colorIcono: colorScheme.error,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
                onPressed: onReintentar, child: const Text("Reintentar")),
          ],
        ),
      ),
    );
  }

  Widget _vistaNetezza(ColorScheme colorScheme) {
    return FutureBuilder<
        ({List<NetezzaSesion> activas, List<NetezzaSesion> idle})>(
      future: _netezzaFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorInfra(
              snapshot.error!,
              () => setState(() =>
                  _netezzaFuture = _infraService.obtenerNetezzaSesiones()));
        }

        final activas = snapshot.data!.activas;
        final idle = snapshot.data!.idle;

        return RefreshIndicator(
          onRefresh: () async {
            setState(
                () => _netezzaFuture = _infraService.obtenerNetezzaSesiones());
            await _netezzaFuture;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _resumen(colorScheme, [
                ("ACTIVAS", "${activas.length}", colorScheme.primary),
                ("IDLE", "${idle.length}", colorScheme.onSurfaceVariant),
                (
                  "TOTAL",
                  "${activas.length + idle.length}",
                  colorScheme.onSurface
                ),
              ]),
              const SizedBox(height: 16),
              if (activas.isEmpty && idle.isEmpty)
                EstadoVacio(
                    icono: Icons.check_circle_outline,
                    mensaje: "Sin sesiones en Netezza ahora mismo",
                    colorIcono: colorScheme.onSurfaceVariant)
              else ...[
                for (final s in activas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaSesionNetezza(
                        sesion: s,
                        onAbortar: () => _abortarNetezza(s.sessionId)),
                  ),
                for (final s in idle)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaSesionNetezza(sesion: s),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _vistaPostgres(ColorScheme colorScheme, {required bool esProd}) {
    final future = esProd ? _prodFuture : _devFuture;
    final soloActivas = esProd ? _soloActivasProd : _soloActivasDev;

    return FutureBuilder<
        ({List<PostgresSesion> filas, int total, int activas})>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorInfra(
            snapshot.error!,
            () => setState(() {
              if (esProd) {
                _prodFuture = _infraService.obtenerPostgresProd(
                    soloActivas: _soloActivasProd);
              } else {
                _devFuture = _infraService.obtenerPostgresDev(
                    soloActivas: _soloActivasDev);
              }
            }),
          );
        }

        final filas = snapshot.data!.filas;
        final bloqueadas = filas.where((f) => f.estaBloqueada).length;

        return RefreshIndicator(
          onRefresh: () async {
            final nuevoFuture = esProd
                ? _infraService.obtenerPostgresProd(
                    soloActivas: _soloActivasProd)
                : _infraService.obtenerPostgresDev(
                    soloActivas: _soloActivasDev);
            setState(() =>
                esProd ? _prodFuture = nuevoFuture : _devFuture = nuevoFuture);
            await nuevoFuture;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _resumen(colorScheme, [
                ("TOTAL", "${snapshot.data!.total}", colorScheme.onSurface),
                ("ACTIVAS", "${snapshot.data!.activas}", StatusColors.info),
                (
                  "BLOQUEADAS",
                  "$bloqueadas",
                  bloqueadas > 0
                      ? StatusColors.critico
                      : colorScheme.onSurfaceVariant
                ),
              ]),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text("Solo activas"),
                  Switch(
                    value: soloActivas,
                    onChanged: (valor) => setState(() {
                      if (esProd) {
                        _soloActivasProd = valor;
                        _prodFuture = _infraService.obtenerPostgresProd(
                            soloActivas: valor);
                      } else {
                        _soloActivasDev = valor;
                        _devFuture = _infraService.obtenerPostgresDev(
                            soloActivas: valor);
                      }
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (filas.isEmpty)
                EstadoVacio(
                    icono: Icons.check_circle_outline,
                    mensaje: "Sin sesiones para mostrar",
                    colorIcono: colorScheme.onSurfaceVariant)
              else
                for (final s in filas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaSesionPostgres(
                      sesion: s,
                      onCancelar: () =>
                          _cancelarPostgres(esProd: esProd, pid: s.pid),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _resumen(
      ColorScheme colorScheme, List<(String, String, Color)> items) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: items[i].$3, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(items[i].$1,
                      style: AppTextStyles.tech(
                          color: colorScheme.onSurfaceVariant, fontSize: 8.5)),
                  const SizedBox(height: 2),
                  Text(items[i].$2,
                      style: TextStyle(
                          color: items[i].$3,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
            ),
          ),
          if (i != items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _PillEscena extends StatelessWidget {
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _PillEscena(
      {required this.texto, required this.seleccionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: seleccionado
                ? colorScheme.primary.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: seleccionado ? colorScheme.primary : Colors.transparent),
          ),
          child: Text(
            texto,
            style: TextStyle(
              color: seleccionado
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
