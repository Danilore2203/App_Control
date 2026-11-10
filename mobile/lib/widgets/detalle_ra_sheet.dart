import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../models/ra_archivo.dart";
import "../services/comandos_service.dart";
import "../services/ra_service.dart";
import "../services/seguimiento_lanzamiento.dart";
import "../services/sesion_actual.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "titulo_seccion.dart";

/// Detalle de un archivo RA, como el modal del Monitor RA de la web: la
/// carpeta del FTP donde se deposita, de que procesos depende (los que lo
/// generan, con su job y un boton para ejecutarlos) y que procesos lo usan.
class DetalleRaSheet extends StatefulWidget {
  const DetalleRaSheet({super.key, required this.archivo, this.servicio, this.lanzar});

  final RaArchivo archivo;

  /// Para las pruebas; normalmente null.
  final RaService? servicio;
  final Future<void> Function(RaDependencia dependencia)? lanzar;

  static Future<void> mostrar(BuildContext context, RaArchivo archivo) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => DetalleRaSheet(archivo: archivo),
      );

  @override
  State<DetalleRaSheet> createState() => _DetalleRaSheetState();
}

class _DetalleRaSheetState extends State<DetalleRaSheet> {
  late final RaService _servicio = widget.servicio ?? RaService();
  late Future<RaDetalle> _detalle = _servicio.obtenerDetalle(widget.archivo.archivo);
  final Set<String> _lanzando = {};

  void _reintentar() => setState(() => _detalle = _servicio.obtenerDetalle(widget.archivo.archivo));

  Future<void> _ejecutar(RaDependencia d) async {
    final esAirflow = d.fuente == "AIRFLOW";
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(esAirflow ? "¿Disparar ${d.proceso}?" : "¿Ejecutar ${d.proceso}?"),
        content: Text(
          esAirflow
              ? "Se crea una corrida manual del DAG en Airflow, como desde el monitor web."
              : "Se lanza en ${d.fuenteLegible} a través de OP, como desde la web. "
                  "Cuando termine, actualiza el RA para ver si el archivo llegó.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Ejecutar")),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _lanzando.add(d.proceso));
    try {
      final lanzar = widget.lanzar;
      if (lanzar != null) {
        await lanzar(d);
      } else {
        await ejecutarYSeguir(
          tipo: "procesos.lanzar",
          payload: {"nombre": d.proceso, "fuente": d.fuente, "ruta": d.ruta ?? ""},
          titulo: esAirflow ? "Disparar ${d.proceso}" : "Ejecutar ${d.proceso}",
          seguir: !esAirflow,
        );
      }
    } catch (_) {
      // La barra flotante del Monitor RA ya muestra el error.
    } finally {
      if (mounted) setState(() => _lanzando.remove(d.proceso));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final a = widget.archivo;
    final tono = colorRa(a.color, colorScheme);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<RaDetalle>(
        future: _detalle,
        builder: (context, snap) {
          final detalle = snap.data;
          final ruta = detalle?.archivo?.ruta ?? a.ruta;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CajaIcono(Icons.description_outlined, color: tono),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      a.archivo,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PillEstado(a.estado, color: tono),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  if (a.fechaHora != null) _Dato(Icons.schedule_rounded, "Cargó ${fechaCatalogo(a.fechaHora) ?? a.fechaHora}"),
                  if (a.tamano != null)
                    _Dato(Icons.straighten_rounded,
                        "${formatearMiles(a.tamano!.round())} B${a.tamanoRef != null ? " · ref ${formatearMiles(a.tamanoRef!.round())} B" : ""}"),
                  if (a.proceso.isNotEmpty) _Dato(Icons.account_tree_outlined, a.proceso),
                ],
              ),
              const SizedBox(height: 16),
              const Eyebrow("Ruta en el FTP"),
              const SizedBox(height: 6),
              _Ruta(ruta: ruta),
              const SizedBox(height: 20),
              if (snap.connectionState == ConnectionState.waiting && detalle == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snap.hasError && detalle == null)
                _ErrorDetalle(error: snap.error, onReintentar: _reintentar)
              else ...[
                _Seccion(
                  titulo: "Depende de",
                  explicacion: "Procesos que generan este archivo. Si no llegó, ejecútalos desde aquí.",
                  vacio: "No tiene procesos de los que dependa.",
                  dependencias: detalle?.dependeDe ?? const [],
                  lanzando: _lanzando,
                  onEjecutar: SesionActual.esAdmin ? _ejecutar : null,
                ),
                const SizedBox(height: 18),
                _Seccion(
                  titulo: "Lo usan",
                  explicacion: "Procesos que se alimentan de este archivo.",
                  vacio: "Ningún proceso lo usa.",
                  dependencias: detalle?.loUsan ?? const [],
                  lanzando: _lanzando,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

Color colorRa(String color, ColorScheme colorScheme) => switch (color) {
      "green" => StatusColors.exitoso,
      "red" => StatusColors.critico,
      "orange" => StatusColors.advertencia,
      "blue" => StatusColors.info,
      _ => colorScheme.outline,
    };

Color _colorEstadoDependencia(String estado, ColorScheme colorScheme) => switch (estado.toUpperCase()) {
      "OK" => StatusColors.exitoso,
      "ERROR" => StatusColors.critico,
      "DEMORADO" => StatusColors.advertencia,
      "EN TIEMPO" => StatusColors.info,
      _ => colorScheme.outline,
    };

String _estadoLegible(String estado) => switch (estado.toUpperCase()) {
      "OK" => "OK",
      "ERROR" => "Error",
      "DEMORADO" => "Demorado",
      "EN TIEMPO" => "En tiempo",
      _ => "Sin registro",
    };

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.texto);

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(child: Text(texto, style: theme.textTheme.bodySmall?.copyWith(color: color))),
      ],
    );
  }
}

class _Ruta extends StatelessWidget {
  const _Ruta({required this.ruta});

  final String? ruta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final texto = ruta;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_rounded, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: texto == null
                ? Text("Sin ruta registrada", style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline))
                : SelectableText(
                    texto,
                    key: const Key("ruta_ftp"),
                    style: AppTextStyles.tech(color: colorScheme.onSurface, fontSize: 12.5, letterSpacing: 0.2),
                  ),
          ),
          if (texto != null)
            IconButton(
              tooltip: "Copiar ruta",
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: texto));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text("Ruta copiada")));
              },
            ),
        ],
      ),
    );
  }
}

class _ErrorDetalle extends StatelessWidget {
  const _ErrorDetalle({required this.error, required this.onReintentar});

  final Object? error;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final texto = error is ComandoFallidoException
        ? (error as ComandoFallidoException).mensaje
        : (error?.toString() ?? "").replaceFirst("Exception: ", "");
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MensajeInline(
          "No se pudieron leer las dependencias: $texto. Si dice que OP no responde o no conoce el "
          "comando, falta reiniciar OP en el servidor .150.",
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text("Reintentar"),
          ),
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.explicacion,
    required this.vacio,
    required this.dependencias,
    required this.lanzando,
    this.onEjecutar,
  });

  final String titulo;
  final String explicacion;
  final String vacio;
  final List<RaDependencia> dependencias;
  final Set<String> lanzando;
  final Future<void> Function(RaDependencia)? onEjecutar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Eyebrow(titulo),
            const SizedBox(width: 8),
            Text("${dependencias.length}",
                style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.outline, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        Text(explicacion, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        if (dependencias.isEmpty)
          Text(vacio, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline))
        else
          for (final d in dependencias)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TarjetaDependencia(
                dependencia: d,
                lanzando: lanzando.contains(d.proceso),
                onEjecutar: onEjecutar == null || !d.lanzable || lanzando.contains(d.proceso)
                    ? null
                    : () => onEjecutar!(d),
                mostrarBoton: onEjecutar != null && d.lanzable,
              ),
            ),
      ],
    );
  }
}

class _TarjetaDependencia extends StatelessWidget {
  const _TarjetaDependencia({
    required this.dependencia,
    required this.lanzando,
    required this.onEjecutar,
    required this.mostrarBoton,
  });

  final RaDependencia dependencia;
  final bool lanzando;
  final VoidCallback? onEjecutar;
  final bool mostrarBoton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final d = dependencia;
    final tono = _colorEstadoDependencia(d.estado, colorScheme);
    final horas = [
      if (d.horaProgramada != null) "Programado ${d.horaProgramada!.length >= 5 ? d.horaProgramada!.substring(0, 5) : d.horaProgramada}",
      if (d.horaLog != null) "última ${fechaCatalogo(d.horaLog) ?? d.horaLog}",
    ].join(" · ");
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tono.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  d.proceso,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              PillEstado(_estadoLegible(d.estado), color: tono),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [if (d.fuenteLegible.isNotEmpty) d.fuenteLegible, if (horas.isNotEmpty) horas].join(" · "),
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          if (d.responsable != null) ...[
            const SizedBox(height: 2),
            Text("Responsable: ${d.responsable}",
                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          ],
          if (d.ruta != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              d.ruta!,
              style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 11, letterSpacing: 0.1),
            ),
          ],
          if (mostrarBoton) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: Key("ejecutar_${d.proceso}"),
                onPressed: onEjecutar,
                icon: lanzando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(lanzando ? "Ejecutando…" : (d.fuente == "AIRFLOW" ? "Disparar DAG" : "Ejecutar")),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
