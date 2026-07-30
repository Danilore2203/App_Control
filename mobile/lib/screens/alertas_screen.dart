import "package:flutter/material.dart";

import "../models/alerta.dart";
import "../models/bitacora_error.dart";
import "../models/control.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../widgets/detalle_proceso_sheet.dart";
import "../widgets/estado_badge.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/monitoreo_por_fuente.dart" show esCore;

/// Reconstruye, a partir de una entrada de bitacora tipo INCOHERENCIA
/// ("proceso -> tabla"), un Control sintetico con los datos reales del
/// proceso (mismo id/fuente/etc) pero con el color forzado a rojo y el
/// estado describiendo la incoherencia, para poder reusar toda la UI de
/// falla critica (tarjeta, alarma de pantalla completa, detalle) sin
/// duplicar esos widgets.
Control? construirFallaDesdeIncoherencia(
    BitacoraError entrada, List<Control> controles) {
  final partes = entrada.nombre.split(" -> ");
  if (partes.length != 2) return null;
  final procesoNombre = partes[0];
  final tablaNombre = partes[1];

  Control? real;
  for (final c in controles) {
    if (c.nombre == procesoNombre) {
      real = c;
      break;
    }
  }
  if (real == null) return null;

  return Control(
    id: real.id,
    nombre: real.nombre,
    fuente: real.fuente,
    estado: "OK, pero $tablaNombre quedo mal (incoherencia)",
    color: "red",
    horaProgramada: real.horaProgramada,
    horaLog: real.horaLog,
    horaFin: real.horaFin,
    core: real.core,
    ruta: real.ruta,
    version: real.version,
    snapshotFecha: real.snapshotFecha,
    snapshotTs: entrada.fechaActualizacion ?? entrada.fechaHora,
  );
}

class AlertasScreen extends StatefulWidget {
  const AlertasScreen({super.key});

  @override
  State<AlertasScreen> createState() => _AlertasScreenState();
}

class _AlertasScreenState extends State<AlertasScreen> {
  final _apiService = ApiService();
  late Future<List<Alerta>> _alertasFuture;
  late Future<List<Control>> _controlesFuture;
  List<BitacoraError> _incoherenciasHoy = [];
  bool _bannerDescartado = false;

  @override
  void initState() {
    super.initState();
    _alertasFuture = _apiService.obtenerAlertas();
    _controlesFuture = _apiService.obtenerControles();
    _cargarIncoherencias();
  }

  Future<void> _cargarIncoherencias() async {
    final ahora = DateTime.now();
    try {
      final entradas =
          await _apiService.obtenerBitacoraEntradas(ahora.year, mes: ahora.month);
      final hoy = entradas
          .where((e) =>
              e.estado == "INCOHERENCIA" &&
              !e.resuelto &&
              e.fechaHora.year == ahora.year &&
              e.fechaHora.month == ahora.month &&
              e.fechaHora.day == ahora.day)
          .toList();
      if (mounted) {
        setState(() => _incoherenciasHoy = hoy);
      }
    } catch (_) {
      // Si falla, simplemente no se suman incoherencias este ciclo.
    }
  }

  Future<void> _recargarAlertas() async {
    final futureAlertas = _apiService.obtenerAlertas();
    final futureControles = _apiService.obtenerControles();
    setState(() {
      _alertasFuture = futureAlertas;
      _controlesFuture = futureControles;
      _bannerDescartado = false;
    });
    _cargarIncoherencias();
    await Future.wait([futureAlertas, futureControles]);
  }

  String _formatearFecha(DateTime fecha) {
    String dosDigitos(int n) => n.toString().padLeft(2, "0");
    return "${dosDigitos(fecha.day)}/${dosDigitos(fecha.month)}/${fecha.year}"
        "  ${dosDigitos(fecha.hour)}:${dosDigitos(fecha.minute)}";
  }

  String _horaControl(Control control) {
    final texto = control.horaFin ?? control.horaLog ?? control.horaProgramada;
    if (texto == null || texto.trim().isEmpty) {
      final ts = control.snapshotTs;
      return "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";
    }
    if (texto.contains(" ")) return texto.split(" ").last.substring(0, 5);
    return texto.length >= 5 ? texto.substring(0, 5) : texto;
  }

  Widget _buildResumenCore(List<Control> controles) {
    final colorScheme = Theme.of(context).colorScheme;
    final core = controles.where(esCore).toList();
    final incoherencias = _incoherenciasHoy
        .map((e) => construirFallaDesdeIncoherencia(e, controles))
        .whereType<Control>()
        .toList();
    final fallando = [
      ...core.where((c) => c.color == "red" || c.color == "orange"),
      ...incoherencias,
    ]..sort((a, b) => a.color == "red" ? -1 : 1);

    if (fallando.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _TarjetaResumen(
                  titulo: "PROCESOS CRÍTICOS",
                  valor: "${fallando.length}",
                  subtitulo: "Acción requerida",
                  color: StatusColors.critico,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TarjetaResumen(
                  titulo: "CORE MONITOREADOS",
                  valor: "${core.length}",
                  subtitulo: "Total vigilado",
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Fallas Críticas",
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text("EN VIVO",
                  style: AppTextStyles.tech(
                      color: colorScheme.primary, fontSize: 10)),
            ],
          ),
        ),
        for (final control in fallando)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _TarjetaFallaCritica(
              control: control,
              hora: _horaControl(control),
              onVerDetalle: () => mostrarDetalleProceso(context, control),
            ),
          ),
        if (!_bannerDescartado)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _BannerCriticoFlotante(
              cantidad: fallando.length,
              onCerrar: () => setState(() => _bannerDescartado = true),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child:
              Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        FutureBuilder<List<Control>>(
          future: _controlesFuture,
          builder: (context, snapshot) =>
              _buildResumenCore(snapshot.data ?? []),
        ),
        Expanded(
          child: FutureBuilder<List<Alerta>>(
            future: _alertasFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return EstadoVacio(
                  icono: Icons.error_outline,
                  mensaje: "No se pudieron cargar las alertas.",
                  colorIcono: colorScheme.error,
                );
              }

              final alertas = snapshot.data ?? [];
              if (alertas.isEmpty) {
                return EstadoVacio(
                  icono: Icons.notifications_off_outlined,
                  mensaje: "Sin alertas por ahora",
                  colorIcono: colorScheme.onSurfaceVariant,
                );
              }

              return RefreshIndicator(
                onRefresh: _recargarAlertas,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: alertas.length,
                  itemBuilder: (context, index) {
                    final alerta = alertas[index];
                    final esCritica = alerta.nivel == "critica";
                    final color = esCritica
                        ? StatusColors.critico
                        : StatusColors.advertencia;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.15),
                          child:
                              Icon(Icons.warning_amber_rounded, color: color),
                        ),
                        title: Text(alerta.mensaje),
                        subtitle: Text(_formatearFecha(alerta.creadoEn)),
                        trailing: EstadoBadge(
                            texto: esCritica ? "Critica" : "Normal",
                            color: color),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  final String titulo;
  final String valor;
  final String subtitulo;
  final Color color;

  const _TarjetaResumen({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 14)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: AppTextStyles.tech(color: color, fontSize: 9)),
          const SizedBox(height: 4),
          Text(valor,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(subtitulo,
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
        ],
      ),
    );
  }
}

class _TarjetaFallaCritica extends StatelessWidget {
  final Control control;
  final String hora;
  final VoidCallback onVerDetalle;

  const _TarjetaFallaCritica(
      {required this.control, required this.hora, required this.onVerDetalle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = control.esDemorado
        ? StatusColors.advertencia
        : StatusColors.critico;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 10),
                child: _PuntoCritico(color: color),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      control.nombre,
                      style: AppTextStyles.tech(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${control.fuente} · ${control.estado}",
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(hora,
                  style: AppTextStyles.tech(
                      color: colorScheme.onSurfaceVariant, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onVerDetalle,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text("VER DETALLE",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PuntoCritico extends StatefulWidget {
  final Color color;

  const _PuntoCritico({required this.color});

  @override
  State<_PuntoCritico> createState() => _PuntoCriticoState();
}

class _PuntoCriticoState extends State<_PuntoCritico>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                  color:
                      widget.color.withValues(alpha: 0.4 * _controller.value),
                  blurRadius: 6 * _controller.value),
            ],
          ),
        );
      },
    );
  }
}

/// Banner flotante y descartable que resume las fallas core actuales, para
/// cuando la alarma de pantalla completa no se disparo (fuera de horario de
/// guardia o guardia desarmada): la falla queda visible aca, sin interrumpir.
class _BannerCriticoFlotante extends StatelessWidget {
  final int cantidad;
  final VoidCallback onCerrar;

  const _BannerCriticoFlotante(
      {required this.cantidad, required this.onCerrar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: StatusColors.critico,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: StatusColors.critico.withValues(alpha: 0.35),
              blurRadius: 20)
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "CRÍTICO: $cantidad proceso${cantidad == 1 ? '' : 's'} core detenido${cantidad == 1 ? '' : 's'}. Revisión manual requerida.",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: onCerrar,
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
