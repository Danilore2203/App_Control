import "package:flutter/material.dart";

import "../models/solicitud_acceso.dart";
import "../services/api_service.dart";
import "../widgets/estado_vacio.dart";

class SolicitudesScreen extends StatefulWidget {
  const SolicitudesScreen({super.key});

  @override
  State<SolicitudesScreen> createState() => _SolicitudesScreenState();
}

class _SolicitudesScreenState extends State<SolicitudesScreen> {
  final _apiService = ApiService();
  late Future<List<SolicitudAcceso>> _solicitudesFuture;
  String? _procesando;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _solicitudesFuture = _apiService.obtenerSolicitudes();
  }

  Future<void> _recargar() async {
    setState(_cargar);
    await _solicitudesFuture;
  }

  Future<void> _aprobar(SolicitudAcceso solicitud) async {
    setState(() => _procesando = "${solicitud.id}-aprobar");
    try {
      await _apiService.aprobarSolicitud(solicitud.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${solicitud.email} aprobado")),
      );
      await _recargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _procesando = null);
    }
  }

  Future<void> _rechazar(SolicitudAcceso solicitud) async {
    setState(() => _procesando = "${solicitud.id}-rechazar");
    try {
      await _apiService.rechazarSolicitud(solicitud.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${solicitud.email} rechazado")),
      );
      await _recargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _procesando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Solicitudes de acceso")),
      body: FutureBuilder<List<SolicitudAcceso>>(
        future: _solicitudesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EstadoVacio(
              icono: Icons.error_outline,
              mensaje: "No se pudieron cargar las solicitudes.",
              colorIcono: colorScheme.error,
            );
          }

          final solicitudes = snapshot.data ?? [];
          if (solicitudes.isEmpty) {
            return EstadoVacio(
              icono: Icons.check_circle_outline,
              mensaje: "No hay solicitudes pendientes",
              colorIcono: colorScheme.onSurfaceVariant,
            );
          }

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: solicitudes.length,
              itemBuilder: (context, index) {
                final solicitud = solicitudes[index];
                final aprobando = _procesando == "${solicitud.id}-aprobar";
                final rechazando = _procesando == "${solicitud.id}-rechazar";
                final ocupado = aprobando || rechazando;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(Icons.person_outline, color: colorScheme.onPrimaryContainer),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    solicitud.nombre ?? solicitud.email,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    solicitud.email,
                                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: ocupado ? null : () => _rechazar(solicitud),
                                icon: rechazando
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.close),
                                label: const Text("Rechazar"),
                                style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: ocupado ? null : () => _aprobar(solicitud),
                                icon: aprobando
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.check),
                                label: const Text("Aprobar"),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
