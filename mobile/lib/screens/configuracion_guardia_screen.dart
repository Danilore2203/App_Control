import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../models/control.dart";
import "../models/historial_falla.dart";
import "../services/api_service.dart";
import "../services/guardia_foreground_task.dart";
import "../services/guardia_service.dart";
import "../services/tono_alarma_service.dart";
import "../theme.dart";
import "../widgets/detalle_proceso_sheet.dart";
import "../widgets/monitoreo_por_fuente.dart" show esCore;

/// Version con AppBar propio, para abrir desde el menu lateral (con boton
/// de volver). El contenido vive en [GuardiaContenido] para poder reusarlo
/// tambien como pestana del bottom nav.
class ConfiguracionGuardiaScreen extends StatelessWidget {
  const ConfiguracionGuardiaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "CONFIGURACIÓN DE GUARDIA",
          style: AppTextStyles.tech(color: colorScheme.onSurface, fontSize: 13),
        ),
      ),
      body: const GuardiaContenido(),
    );
  }
}

/// Configuracion del monitoreo on-call: armar/desarmar la guardia, horario
/// en el que se espera estar de guardia, tono de alarma preferido y los
/// procesos "core" que se vigilan de cerca. El armado/horario/tono son
/// preferencias del dispositivo (se guardan localmente); los procesos
/// vigilados y el historial de fallas son datos reales del backend.
class GuardiaContenido extends StatefulWidget {
  const GuardiaContenido({super.key});

  @override
  State<GuardiaContenido> createState() => _GuardiaContenidoState();
}

class _GuardiaContenidoState extends State<GuardiaContenido> {
  final _apiService = ApiService();
  final _guardiaService = GuardiaService();

  bool _cargandoPreferencias = true;
  bool _probandoAlerta = false;
  bool _cambiandoTono = false;
  bool _armado = false;
  String _horaInicio = "00:00";
  String _horaFin = "00:00";
  String? _tonoUri;
  String? _nombreTono;

  late Future<List<Control>> _controlesFuture;
  late Future<List<HistorialFalla>> _historialFuture;

  @override
  void initState() {
    super.initState();
    _controlesFuture = _apiService.obtenerControles();
    _historialFuture = _apiService.obtenerHistorialFallas();
    _cargarPreferencias();
  }

  Future<void> _cargarPreferencias() async {
    // Si el almacenamiento seguro falla en algun dispositivo (p.ej. una clave
    // de encriptacion huerfana tras desinstalar/reinstalar), no debe dejar la
    // pantalla girando para siempre: se usan los valores por defecto y se
    // sigue adelante igual.
    const limite = Duration(seconds: 5);
    try {
      final armado = await _guardiaService
          .obtenerArmado()
          .timeout(limite, onTimeout: () => false);
      final inicio = await _guardiaService
          .obtenerHoraInicio()
          .timeout(limite, onTimeout: () => "00:00");
      final fin = await _guardiaService
          .obtenerHoraFin()
          .timeout(limite, onTimeout: () => "00:00");
      final tonoUri = await _guardiaService
          .obtenerTonoUri()
          .timeout(limite, onTimeout: () => null);
      if (!mounted) return;
      setState(() {
        _armado = armado;
        _horaInicio = inicio;
        _horaFin = fin;
        _tonoUri = tonoUri;
        _cargandoPreferencias = false;
      });
      // Si quedo armada de una sesion anterior pero el servicio no esta
      // corriendo (p.ej. Android lo mato), se reconcilia aca.
      if (armado) establecerGuardiaActiva(true);
      _cargarNombreTono();
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoPreferencias = false);
    }
  }

  Future<void> _cargarNombreTono() async {
    if (_tonoUri == null) {
      setState(() => _nombreTono = null);
      return;
    }
    final nombre = await nombreTonoAlarma(_tonoUri);
    if (!mounted) return;
    setState(() => _nombreTono = nombre);
  }

  Future<void> _elegirTono() async {
    setState(() => _cambiandoTono = true);
    try {
      final elegido = await elegirTonoAlarmaDelSistema(uriActual: _tonoUri);
      // null = el usuario cancelo el selector, no que haya elegido "Ninguno"
      // (Android no distingue eso en el resultado); si cancela se deja el
      // tono como estaba.
      if (elegido == null) return;
      await _guardiaService.guardarTonoUri(elegido);
      if (!mounted) return;
      setState(() => _tonoUri = elegido);
      await _cargarNombreTono();
    } finally {
      if (mounted) setState(() => _cambiandoTono = false);
    }
  }

  TimeOfDay _aTimeOfDay(String texto) {
    final partes = texto.split(":");
    return TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]));
  }

  String _deTimeOfDay(TimeOfDay hora) =>
      "${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}";

  Future<void> _elegirHora({required bool esInicio}) async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _aTimeOfDay(esInicio ? _horaInicio : _horaFin),
    );
    if (hora == null) return;
    setState(() {
      if (esInicio) {
        _horaInicio = _deTimeOfDay(hora);
      } else {
        _horaFin = _deTimeOfDay(hora);
      }
    });
    await _guardiaService.guardarHorario(inicio: _horaInicio, fin: _horaFin);
  }

  Future<void> _probarAlerta() async {
    setState(() => _probandoAlerta = true);
    try {
      await _apiService.probarAlerta();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Push de prueba enviada. Debería sonar en unos segundos."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _probandoAlerta = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return _cargandoPreferencias
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _tarjetaArmado(colorScheme),
              const SizedBox(height: 24),
              _tituloSeccion("HORARIO DE GUARDIA", colorScheme),
              const SizedBox(height: 10),
              _tarjetaHorario(colorScheme),
              const SizedBox(height: 24),
              _tituloSeccion("TONO DE ALARMA (CRÍTICO)", colorScheme),
              const SizedBox(height: 10),
              _tarjetaTono(colorScheme),
              const SizedBox(height: 24),
              _seccionProcesosVigilados(colorScheme),
              const SizedBox(height: 24),
              _tituloSeccion("FALLAS RECIENTES (7 DÍAS)", colorScheme),
              const SizedBox(height: 10),
              _graficoHistorial(colorScheme),
              const SizedBox(height: 16),
            ],
          );
  }

  Widget _tituloSeccion(String texto, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(texto,
          style: AppTextStyles.tech(
              color: colorScheme.onSurfaceVariant, fontSize: 10)),
    );
  }

  Widget _tarjetaArmado(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _armado
                ? colorScheme.primary.withValues(alpha: 0.5)
                : Colors.transparent),
        boxShadow: _armado
            ? [
                BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    blurRadius: 20)
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Monitoreo de guardia",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Activar alerta crítica sonora en este dispositivo",
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _armado,
                onChanged: (valor) {
                  setState(() => _armado = valor);
                  _guardiaService.guardarArmado(valor);
                  establecerGuardiaActiva(valor);
                  HapticFeedback.selectionClick();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _casillaEstado(
                  colorScheme,
                  titulo: "ESTADO",
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _armado
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _armado ? "ARMADO" : "DESARMADO",
                        style: AppTextStyles.tech(
                          color: _armado
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _casillaEstado(
                  colorScheme,
                  titulo: "RESPUESTA",
                  child: Text(
                    "ALERTA SONORA",
                    style: AppTextStyles.tech(
                        color: colorScheme.onSurface, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _probandoAlerta ? null : _probarAlerta,
              icon: _probandoAlerta
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text("Probar alerta ahora"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _casillaEstado(ColorScheme colorScheme,
      {required String titulo, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: AppTextStyles.tech(
                  color: colorScheme.onSurfaceVariant, fontSize: 8.5)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _tarjetaHorario(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
              child: _columnaHora("INICIO", _horaInicio, colorScheme,
                  () => _elegirHora(esInicio: true))),
          Icon(Icons.arrow_forward,
              color: colorScheme.onSurfaceVariant, size: 18),
          Expanded(
              child: _columnaHora("FIN", _horaFin, colorScheme,
                  () => _elegirHora(esInicio: false))),
        ],
      ),
    );
  }

  Widget _columnaHora(String etiqueta, String valor, ColorScheme colorScheme,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(etiqueta,
                style: AppTextStyles.tech(
                    color: colorScheme.onSurfaceVariant, fontSize: 9)),
            const SizedBox(height: 6),
            Text(
              valor,
              style: AppTextStyles.tech(
                  color: colorScheme.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaTono(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.music_note_outlined, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nombreTono ?? "Predeterminado del sistema",
                  style: TextStyle(
                      color: colorScheme.onSurface, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  "Uno de los tonos de alarma ya instalados en el celular",
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _cambiandoTono
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _elegirTono,
                  child: const Text("Cambiar"),
                ),
        ],
      ),
    );
  }

  Widget _seccionProcesosVigilados(ColorScheme colorScheme) {
    return FutureBuilder<List<Control>>(
      future: _controlesFuture,
      builder: (context, snapshot) {
        final controles = snapshot.data ?? [];
        final core = controles.where(esCore).toList()
          ..sort((a, b) {
            const orden = {
              "red": 0,
              "orange": 1,
              "blue": 2,
              "green": 3,
              "gray": 4
            };
            return (orden[a.color] ?? 5).compareTo(orden[b.color] ?? 5);
          });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "PROCESOS BAJO VIGILANCIA",
                    style: AppTextStyles.tech(
                        color: colorScheme.onSurfaceVariant, fontSize: 10),
                  ),
                  Text(
                    "${core.length} ACTIVOS",
                    style: AppTextStyles.tech(
                        color: colorScheme.primary, fontSize: 10),
                  ),
                ],
              ),
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (core.isEmpty)
              Text(
                "No hay procesos marcados como core.",
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else
              for (final control in core)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FilaProcesoVigilado(
                    control: control,
                    onTap: () => mostrarDetalleProceso(context, control),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _graficoHistorial(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: FutureBuilder<List<HistorialFalla>>(
        future: _historialFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final datos = snapshot.data ?? [];
          if (datos.isEmpty) {
            return SizedBox(
              height: 60,
              child: Center(
                child: Text("Sin historial todavía",
                    style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ),
            );
          }

          final maxValor =
              datos.map((d) => d.fallas).reduce((a, b) => a > b ? a : b);
          final indiceMax = datos.indexWhere((d) => d.fallas == maxValor);

          return Column(
            children: [
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < datos.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                "${datos[i].fallas}",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: i == indiceMax
                                      ? StatusColors.critico
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: i == indiceMax
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: maxValor == 0
                                    ? 4
                                    : (datos[i].fallas / maxValor) * 76 + 4,
                                decoration: BoxDecoration(
                                  color: i == indiceMax
                                      ? StatusColors.critico
                                      : colorScheme.primary
                                          .withValues(alpha: 0.35),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fechaCorta(datos.first.fecha),
                      style: TextStyle(
                          fontSize: 9,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6))),
                  Text(
                    "${_fechaCorta(datos[indiceMax].fecha)} (pico)",
                    style: const TextStyle(
                        fontSize: 9, color: StatusColors.critico),
                  ),
                  Text(_fechaCorta(datos.last.fecha),
                      style: TextStyle(
                          fontSize: 9,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6))),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _fechaCorta(DateTime fecha) =>
      "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}";
}

class _FilaProcesoVigilado extends StatelessWidget {
  final Control control;
  final VoidCallback onTap;

  const _FilaProcesoVigilado({required this.control, required this.onTap});

  Color _color(ColorScheme colorScheme) {
    if (control.esDemorado) return StatusColors.advertencia;
    switch (control.color) {
      case "red":
        return StatusColors.critico;
      case "orange":
        return StatusColors.advertencia;
      case "blue":
        return StatusColors.info;
      case "green":
        return StatusColors.exitoso;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  IconData get _icono {
    switch (control.fuente) {
      case "DATASTAGE":
        return Icons.dns_outlined;
      case "PENTAHO":
        return Icons.account_tree_outlined;
      case "AIRFLOW":
        return Icons.air;
      default:
        return Icons.memory;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _color(colorScheme);
    final esFalla = control.color == "red" || control.color == "orange";

    return Material(
      color: esFalla
          ? color.withValues(alpha: 0.08)
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: esFalla
                    ? color.withValues(alpha: 0.35)
                    : Colors.transparent),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Center(
                        child: Icon(_icono,
                            color: esFalla
                                ? color
                                : colorScheme.onSurfaceVariant)),
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border:
                              Border.all(color: colorScheme.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      control.nombre,
                      style: TextStyle(
                        color: esFalla ? color : colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${control.fuente} · ${control.estado}",
                      style: TextStyle(
                        color: esFalla
                            ? color.withValues(alpha: 0.7)
                            : colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                esFalla ? Icons.error_outline : Icons.chevron_right,
                color: esFalla
                    ? color
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
