import "package:flutter/material.dart";

import "../models/solicitud_acceso.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/fondo_app.dart";
import "../widgets/titulo_seccion.dart";

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
      await _apiService.aprobarSolicitud(solicitud);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${solicitud.identificador} aprobado")),
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
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Rechazar solicitud?"),
        content: Text(
          "Se rechaza la solicitud de ${solicitud.identificador}. Esta acción no se puede deshacer.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text("Rechazar", style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _procesando = "${solicitud.id}-rechazar");
    try {
      await _apiService.rechazarSolicitud(solicitud);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${solicitud.identificador} rechazado")),
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
              icono: Icons.cloud_off_rounded,
              mensaje: "No se pudieron cargar las solicitudes",
              colorIcono: colorScheme.error,
              onReintentar: _recargar,
            );
          }

          final solicitudes = snapshot.data ?? [];
          if (solicitudes.isEmpty) {
            return const EstadoVacio(
              icono: Icons.check_circle_outline_rounded,
              mensaje: "No hay solicitudes pendientes",
              detalle: "Cuando alguien pida acceso, aparece acá para aprobarlo.",
              colorIcono: StatusColors.exitoso,
            );
          }

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: solicitudes.length,
              itemBuilder: (context, index) {
                final solicitud = solicitudes[index];
                final aprobando = _procesando == "${solicitud.id}-aprobar";
                final rechazando = _procesando == "${solicitud.id}-rechazar";
                final ocupado = aprobando || rechazando;
                final esRegistro = solicitud.tipo == "registro";

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Vidrio(
                    padding: const EdgeInsets.all(14),
                    blur: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CajaIcono(esRegistro ? Icons.badge_outlined : Icons.mail_outline_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    solicitud.identificador,
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (solicitud.email != null) solicitud.email!,
                                      if (solicitud.username != null) "@${solicitud.username}",
                                    ].join(" · "),
                                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            PillEstado(esRegistro ? "Registro" : "Google", color: colorScheme.onSurfaceVariant),
                          ],
                        ),
                        const SizedBox(height: 14),
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
                                    : const Icon(Icons.close_rounded, size: 18),
                                label: const Text("Rechazar"),
                                style: OutlinedButton.styleFrom(foregroundColor: StatusColors.critico),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: ocupado ? null : () => _aprobar(solicitud),
                                icon: aprobando
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.check_rounded, size: 18),
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
