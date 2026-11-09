import "package:flutter/material.dart";

import "../models/alerta.dart";
import "../models/bitacora_error.dart";
import "../models/control.dart";
import "../services/actualizaciones_service.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../widgets/detalle_proceso_sheet.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/fondo_app.dart";
import "../widgets/monitoreo_por_fuente.dart" show esCore;
import "../widgets/titulo_seccion.dart";

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
  late final SuscripcionActualizaciones _actualizaciones;

  @override
  void initState() {
    super.initState();
    _alertasFuture = _apiService.obtenerAlertas();
    _controlesFuture = _apiService.obtenerControles();
    _cargarIncoherencias();
    // Refresca cuando el backend avisa que hay datos nuevos (y al volver a
    // primer plano), en vez de preguntar cada 60 s aunque no haya nada.
    _actualizaciones = SuscripcionActualizaciones(() {
      if (!mounted) return;
      setState(() {
        _alertasFuture = _apiService.obtenerAlertas();
        _controlesFuture = _apiService.obtenerControles();
      });
      _cargarIncoherencias();
    });
  }

  @override
  void dispose() {
    _actualizaciones.cancelar();
    super.dispose();
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
        " · ${dosDigitos(fecha.hour)}:${dosDigitos(fecha.minute)}";
  }

  String _horaControl(Control control) {
    final texto = control.horaFin ?? control.horaLog ?? control.horaProgramada;
    if (texto == null || texto.trim().isEmpty) {
      final ts = control.snapshotTs;
      return "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";
    }
    // "2026-11-05 08:47:00" -> "08:47"; si la parte de la hora viene mas
    // corta ("8:47", "N/A"), se devuelve tal cual: substring(0, 5) a ciegas
    // tiraba RangeError y rompia toda la pestana.
    final parte = texto.contains(" ") ? texto.split(" ").last : texto;
    return parte.length >= 5 ? parte.substring(0, 5) : parte;
  }

  List<Control> _fallandoCore(List<Control> controles) {
    final core = controles.where(esCore).toList();
    final incoherencias = _incoherenciasHoy
        .map((e) => construirFallaDesdeIncoherencia(e, controles))
        .whereType<Control>()
        .toList();
    return [
      ...core.where((c) => c.color == "red" || c.color == "orange"),
      ...incoherencias,
    ]..sort((a, b) => a.color == "red" ? -1 : 1);
  }

  List<Widget> _seccionCore(List<Control> controles) {
    final core = controles.where(esCore).toList();
    final fallando = _fallandoCore(controles);
    final hayFallas = fallando.isNotEmpty;

    return [
      Row(
        children: [
          Expanded(
            child: IndicadorTile(
              etiqueta: "Core en falla",
              valor: "${fallando.length}",
              icono: hayFallas ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: hayFallas ? StatusColors.critico : StatusColors.exitoso,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: IndicadorTile(
              etiqueta: "Core vigilados",
              valor: "${core.length}",
              icono: Icons.shield_outlined,
            ),
          ),
        ],
      ),
      if (hayFallas) ...[
        const SizedBox(height: 22),
        const TituloSeccion(
          "Fallas críticas",
          accion: PillEstado("En vivo", color: StatusColors.critico, icono: Icons.circle),
        ),
        const SizedBox(height: 10),
        for (final control in fallando)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TarjetaFallaCritica(
              control: control,
              hora: _horaControl(control),
              onVerDetalle: () => mostrarDetalleProceso(context, control),
            ),
          ),
        if (!_bannerDescartado)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MensajeInline(
              "${fallando.length} proceso${fallando.length == 1 ? '' : 's'} core detenido${fallando.length == 1 ? '' : 's'}. Revisión manual requerida.",
              icono: Icons.campaign_rounded,
              onCerrar: () => setState(() => _bannerDescartado = true),
            ),
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<List<Alerta>>(
      future: _alertasFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EstadoVacio(
            icono: Icons.cloud_off_rounded,
            mensaje: "No se pudieron cargar las alertas",
            detalle: "Revisá la conexión e intentá de nuevo.",
            colorIcono: colorScheme.error,
            onReintentar: _recargarAlertas,
          );
        }

        final alertas = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: _recargarAlertas,
          child: FutureBuilder<List<Control>>(
            future: _controlesFuture,
            builder: (context, controlesSnapshot) {
              final controles = controlesSnapshot.data ?? [];
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  ..._seccionCore(controles),
                  const SizedBox(height: 22),
                  TituloSeccion(
                    "Historial de alertas",
                    accion: Text(
                      "${alertas.length}",
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (alertas.isEmpty)
                    EstadoVacio(
                      icono: Icons.notifications_off_outlined,
                      mensaje: "Sin alertas por ahora",
                      detalle: "Cuando un proceso core falle, la alerta va a aparecer acá.",
                      colorIcono: colorScheme.outline,
                    )
                  else
                    for (final alerta in alertas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TarjetaAlerta(
                          alerta: alerta,
                          fecha: _formatearFecha(alerta.creadoEn),
                        ),
                      ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _TarjetaAlerta extends StatelessWidget {
  const _TarjetaAlerta({required this.alerta, required this.fecha});

  final Alerta alerta;
  final String fecha;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final esCritica = alerta.nivel == "critica";
    final color = esCritica ? StatusColors.critico : StatusColors.advertencia;

    return Vidrio(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      blur: 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CajaIcono(
            esCritica ? Icons.notification_important_rounded : Icons.notifications_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alerta.mensaje,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 13, color: colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      fecha,
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PillEstado(esCritica ? "Crítica" : "Normal", color: color),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = control.esDemorado
        ? StatusColors.advertencia
        : StatusColors.critico;

    return Vidrio(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      borderColor: color.withValues(alpha: 0.4),
      color: color.withValues(alpha: 0.08),
      onTap: onVerDetalle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 10),
                child: _PuntoCritico(color: color),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      control.nombre,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${control.fuente} · ${control.estado}",
                      style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hora,
                style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 11, letterSpacing: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                "Ver detalle",
                style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_forward_rounded, size: 16, color: color),
            ],
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
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                  color:
                      widget.color.withValues(alpha: 0.5 * _controller.value),
                  blurRadius: 8 * _controller.value,
                  spreadRadius: 1.5 * _controller.value),
            ],
          ),
        );
      },
    );
  }
}
