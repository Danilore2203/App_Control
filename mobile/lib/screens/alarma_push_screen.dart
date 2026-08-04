import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../services/guardia_foreground_task.dart";
import "../services/notification_service.dart";
import "../theme.dart";

/// Pantalla de alarma tipo despertador: se abre sola cuando llega una alerta
/// critica por push, sin importar si la app estaba minimizada, cerrada o el
/// celular bloqueado (Android la lanza directo sobre la pantalla de bloqueo).
/// El sonido lo repite Android mismo (notificacion FLAG_INSISTENT con el
/// sonido de alarma del sistema, ver notification_service.dart) hasta que se
/// cancela aca -no es un audio que loopee la app- para que sea el mismo
/// sonido de alarma del celular y siga sonando aunque el motor de Flutter no
/// este corriendo.
class AlarmaPushScreen extends StatefulWidget {
  final int id;
  final String titulo;
  final String mensaje;
  final bool esDemorado;
  // true cuando esta pantalla es lo primero que se ve (la app se abrio
  // SOLA por la alarma - notificacion tocada o fullScreenIntent con el
  // celular bloqueado), no cuando ya estaba abierta y la alarma la
  // interrumpio. En ese caso hay que cerrar la app entera al apagar, no
  // solo esta pantalla: si no, "apagar" revela el dashboard atras -la app
  // real- en vez de devolver al celular a la pantalla de bloqueo de donde
  // vino.
  final bool esLanzamiento;

  const AlarmaPushScreen({
    super.key,
    required this.id,
    required this.titulo,
    required this.mensaje,
    this.esDemorado = false,
    this.esLanzamiento = false,
  });

  @override
  State<AlarmaPushScreen> createState() => _AlarmaPushScreenState();
}

class _AlarmaPushScreenState extends State<AlarmaPushScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulso;

  @override
  void initState() {
    super.initState();
    _pulso = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    HapticFeedback.heavyImpact();
  }

  void _apagar() {
    apagarAlarmaLocal(widget.id);
    if (widget.esLanzamiento) {
      // Cierra la app entera (no solo esta pantalla): con el celular
      // bloqueado, esto devuelve a la pantalla de bloqueo real en vez de
      // dejar ver el dashboard de la app atras.
      SystemNavigator.pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// A diferencia de "Apagar alarma" (que solo corta el sonido de esta
  /// vez), esto confirma que el proceso ya se solucino: no vuelve a
  /// alarmar/recordar por esta misma falla aunque el origen todavia no
  /// reporte verde (ver marcarErrorCorregido).
  void _marcarCorregido() {
    marcarErrorCorregido(widget.id);
    _apagar();
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Mismo sonido/urgencia para demorado y error, pero no es lo mismo un
    // proceso que se demoro que uno que fallo de verdad: se pinta distinto.
    final color = widget.esDemorado ? StatusColors.advertencia : StatusColors.critico;

    return PopScope(
      // No se cierra con el boton "atras" del celular: solo con el boton de
      // apagar, como una alarma real.
      canPop: false,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.3,
              colors: [color.withValues(alpha: 0.18), colorScheme.surface],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulso,
                      builder: (context, _) {
                        final t = _pulso.value;
                        return Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withValues(alpha: 0.2),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.25 + t * 0.25),
                                blurRadius: 44 + t * 20,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(Icons.notifications_active, color: color, size: 62),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration:
                          BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        widget.esDemorado ? "ALARMA · DEMORADO" : "ALARMA CRÍTICA",
                        style: AppTextStyles.tech(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.titulo,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.mensaje,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _apagar,
                        icon: const Icon(Icons.notifications_off_outlined),
                        label: const Text(
                          "APAGAR ALARMA",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _marcarCorregido,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text(
                          "ERROR CORREGIDO",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
