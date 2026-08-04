import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../services/api_service.dart";
import "../services/guardia_service.dart";
import "../services/notification_service.dart";
import "../theme.dart";

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

  bool _cargando = true;
  bool _notificacionesHabilitadas = true;
  bool _actualizandoNotificaciones = false;
  String? _error;

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
      if (!mounted) return;
      setState(() {
        _notificacionesHabilitadas = habilitadas;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
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
      if (!mounted) return;
      setState(() => _notificacionesHabilitadas = habilitadas);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _actualizandoNotificaciones = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: const Text("Ajustes")),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.onErrorContainer, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  "NOTIFICACIONES",
                  style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 10),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Recibir notificaciones",
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Incluye alertas críticas y avisos normales de procesos. "
                              "Al desactivar, este dispositivo deja de recibir push del todo.",
                              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _actualizandoNotificaciones
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch(
                              value: _notificacionesHabilitadas,
                              onChanged: _cambiarNotificaciones,
                            ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
