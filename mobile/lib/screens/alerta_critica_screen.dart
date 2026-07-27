import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../models/control.dart";
import "../services/alarma_service.dart";
import "../services/guardia_service.dart";
import "../theme.dart";
import "../widgets/detalle_proceso_sheet.dart";

/// Pantalla completa de alarma: se muestra cuando un proceso marcado como
/// "core" (columna `core` de dataops_catalogo_procesos) esta en falla.
/// Ocupa toda la pantalla a proposito, como una alarma real, en vez de ser
/// una tarjeta mas entre las alertas normales.
class AlertaCriticaScreen extends StatefulWidget {
  final List<Control> controles;

  const AlertaCriticaScreen({super.key, required this.controles});

  @override
  State<AlertaCriticaScreen> createState() => _AlertaCriticaScreenState();
}

class _AlertaCriticaScreenState extends State<AlertaCriticaScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulso;
  final _alarmaService = AlarmaService();
  final _guardiaService = GuardiaService();

  @override
  void initState() {
    super.initState();
    _pulso =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    HapticFeedback.heavyImpact();
    _iniciarSonido();
  }

  Future<void> _iniciarSonido() async {
    final armado = await _guardiaService.obtenerArmado();
    if (!armado || !mounted) return;
    final tono = await _guardiaService.obtenerTono();
    _alarmaService.reproducirEnBucle(tono);
  }

  @override
  void dispose() {
    _pulso.dispose();
    _alarmaService.detener();
    _alarmaService.dispose();
    super.dispose();
  }

  String _formatearFecha(DateTime fecha) {
    String dosDigitos(int n) => n.toString().padLeft(2, "0");
    return "${dosDigitos(fecha.day)}/${dosDigitos(fecha.month)}/${fecha.year}"
        "  ${dosDigitos(fecha.hour)}:${dosDigitos(fecha.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final peor = widget.controles.first;
    final color =
        peor.color == "red" ? StatusColors.critico : StatusColors.advertencia;
    final textoSobrePill =
        peor.color == "red" ? Colors.white : colorScheme.onPrimary;
    final restantes = widget.controles.length - 1;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.3,
            colors: [
              color.withValues(alpha: 0.16),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: Icon(Icons.close,
                          color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _pulso,
                    builder: (context, _) {
                      final t = _pulso.value;
                      return Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.18),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.25 + t * 0.25),
                              blurRadius: 40 + t * 20,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: Icon(Icons.warning_amber_rounded,
                            color: color, size: 58),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      "ALERTA CRÍTICA · CORE",
                      style: AppTextStyles.tech(
                          color: textoSobrePill, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    "FALLO CRÍTICO DETECTADO",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (restantes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        "y $restantes proceso${restantes == 1 ? '' : 's'} core más en falla",
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 26),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _FilaTecnica(
                            etiqueta: "PROCESO",
                            valor: peor.nombre,
                            color: color),
                        const Divider(height: 18),
                        _FilaTecnica(etiqueta: "FUENTE", valor: peor.fuente),
                        const Divider(height: 18),
                        _FilaTecnica(
                            etiqueta: "ESTADO",
                            valor: peor.estado,
                            color: color),
                        const Divider(height: 18),
                        _FilaTecnica(
                          etiqueta: "ÚLTIMA LECTURA",
                          valor: _formatearFecha(peor.snapshotTs),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: textoSobrePill,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.notifications_off_outlined),
                      label: const Text(
                        "DESCARTAR ALERTA",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        side: BorderSide(color: colorScheme.primary),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => mostrarDetalleProceso(context, peor),
                      icon: const Icon(Icons.terminal, size: 18),
                      label: const Text("VER DETALLE"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilaTecnica extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final Color? color;

  const _FilaTecnica({required this.etiqueta, required this.valor, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          etiqueta,
          style: AppTextStyles.tech(
              color: colorScheme.onSurfaceVariant, fontSize: 10),
        ),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.tech(
              color: color ?? colorScheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
