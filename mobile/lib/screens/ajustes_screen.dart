import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../services/api_service.dart";
import "../services/guardia_service.dart";
import "../services/notification_service.dart";
import "../widgets/titulo_seccion.dart";

/// Ajustes generales de la app, aparte de la configuracion de guardia
/// (horario/tono), que ya tiene su propia pantalla.
class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  final _guardiaService = GuardiaService();
  final _apiService = ApiService();

  static const _opcionesVentanaGracia = [0, 1, 5, 10, 15, 30];

  bool _cargando = true;
  bool _notificacionesHabilitadas = true;
  bool _actualizandoNotificaciones = false;
  String? _error;
  String? _diagnosticoFcm;
  int _ventanaGraciaMinutos = 5;

  @override
  void initState() {
    super.initState();
    _cargarPreferencias();
  }

  Future<void> _cargarPreferencias() async {
    try {
      final habilitadas = await _guardiaService
          .obtenerNotificacionesHabilitadas()
          .timeout(const Duration(seconds: 5), onTimeout: () => true);
      final diagnostico = await _guardiaService.obtenerDiagnosticoFcm();
      final ventanaGracia = await _guardiaService.obtenerVentanaGraciaBiometriaMinutos();
      if (!mounted) return;
      setState(() {
        _notificacionesHabilitadas = habilitadas;
        _diagnosticoFcm = diagnostico;
        _ventanaGraciaMinutos = ventanaGracia;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarVentanaGracia(int? minutos) async {
    if (minutos == null) return;
    HapticFeedback.selectionClick();
    await _guardiaService.guardarVentanaGraciaBiometriaMinutos(minutos);
    if (!mounted) return;
    setState(() => _ventanaGraciaMinutos = minutos);
  }

  Future<void> _cambiarNotificaciones(bool habilitadas) async {
    setState(() {
      _actualizandoNotificaciones = true;
      _error = null;
    });
    HapticFeedback.selectionClick();

    try {
      // Se guarda primero: inicializar() lee esta misma preferencia antes
      // de registrar el token, asi que si se guardara despues, activar el
      // switch leeria todavia el valor viejo (false) y no registraria nada.
      await _guardiaService.guardarNotificacionesHabilitadas(habilitadas);
      if (habilitadas) {
        // Vuelve a pedir permisos/token y lo registra en el backend.
        await NotificationService().inicializar();
      } else {
        // Se borra el token en el servidor: el poller ni intenta mandar
        // push a este dispositivo (no alcanza con ignorarlo del lado
        // del cliente).
        await _apiService.eliminarFcmToken();
      }
      final diagnostico = await _guardiaService.obtenerDiagnosticoFcm();
      if (!mounted) return;
      setState(() {
        _notificacionesHabilitadas = habilitadas;
        _diagnosticoFcm = diagnostico;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _actualizandoNotificaciones = false);
    }
  }

  String _etiquetaGracia(int minutos) => minutos == 0 ? "Siempre" : "$minutos min";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Ajustes")),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_error != null) ...[
                  MensajeInline(_error!),
                  const SizedBox(height: 16),
                ],
                const TituloSeccion("Notificaciones"),
                const SizedBox(height: 10),
                FilaOpcion(
                  icono: Icons.notifications_active_outlined,
                  titulo: "Recibir notificaciones",
                  subtitulo: "Alertas críticas y avisos de procesos. Al desactivar, este "
                      "dispositivo deja de recibir push del todo.",
                  trailing: _actualizandoNotificaciones
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Switch(
                          value: _notificacionesHabilitadas,
                          onChanged: _cambiarNotificaciones,
                        ),
                ),
                if (_diagnosticoFcm != null && _diagnosticoFcm != "ok") ...[
                  const SizedBox(height: 10),
                  MensajeInline(
                    "Diagnóstico de notificaciones: $_diagnosticoFcm",
                    icono: Icons.info_outline_rounded,
                  ),
                ],
                const SizedBox(height: 22),
                const TituloSeccion("Seguridad"),
                const SizedBox(height: 10),
                FilaOpcion(
                  icono: Icons.fingerprint_rounded,
                  titulo: "Volver a pedir huella después de",
                  subtitulo: "Si reabrís la app dentro de este tiempo desde el último "
                      "ingreso, no vuelve a pedir huella. \"Siempre\" la pide cada vez.",
                  trailing: PopupMenuButton<int>(
                    initialValue: _ventanaGraciaMinutos,
                    onSelected: _cambiarVentanaGracia,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    itemBuilder: (context) => [
                      for (final minutos in _opcionesVentanaGracia)
                        PopupMenuItem(value: minutos, child: Text(_etiquetaGracia(minutos))),
                    ],
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _etiquetaGracia(_ventanaGraciaMinutos),
                            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.expand_more_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
