import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/actualizaciones_service.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../utils/meses_es.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/titulo_seccion.dart";
import "bitacora_mes_screen.dart";

/// Version con AppBar propio, para abrir desde el menu lateral. El contenido
/// vive en [BitacoraContenido] para poder reusarlo tambien como pestana.
class BitacoraScreen extends StatelessWidget {
  const BitacoraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bitácora")),
      body: const BitacoraContenido(),
    );
  }
}

/// Bitácora de errores: la misma que ve el monitor web (replicada desde
/// OP_PROD), más las entradas manuales e incoherencias propias de la app.
/// Arriba, lo que importa ahora (abiertos, hoy, semana); abajo, el año mes
/// a mes con volumen relativo y cuántos episodios siguen abiertos.
class BitacoraContenido extends StatefulWidget {
  const BitacoraContenido({super.key});

  @override
  State<BitacoraContenido> createState() => _BitacoraContenidoState();
}

class _BitacoraContenidoState extends State<BitacoraContenido> {
  final _apiService = ApiService();
  late int _anio;
  late Future<BitacoraResumenAnio> _resumenFuture;
  late final SuscripcionActualizaciones _actualizaciones;

  @override
  void initState() {
    super.initState();
    _anio = DateTime.now().year;
    _cargar();
    _actualizaciones = SuscripcionActualizaciones(() {
      if (mounted) setState(_cargar);
    });
  }

  @override
  void dispose() {
    _actualizaciones.cancelar();
    super.dispose();
  }

  void _cargar() {
    _resumenFuture = _apiService.obtenerBitacoraResumen(_anio);
  }

  Future<void> _recargar() async {
    setState(_cargar);
    try {
      await _resumenFuture;
    } catch (_) {
      // El FutureBuilder muestra el error.
    }
  }

  void _cambiarAnio(int delta) {
    setState(() {
      _anio += delta;
      _cargar();
    });
  }

  Future<void> _abrirMes(int mes) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => BitacoraMesScreen(anio: _anio, mes: mes)),
    );
    if (mounted) setState(_cargar);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ahora = DateTime.now();

    return FutureBuilder<BitacoraResumenAnio>(
      future: _resumenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EstadoVacio(
            icono: Icons.error_outline,
            mensaje: "No se pudo cargar la bitácora.",
            colorIcono: colorScheme.error,
            onReintentar: _recargar,
          );
        }

        final resumen = snapshot.data!;
        final esAnioActual = resumen.anio == ahora.year;
        final maximoMes = resumen.meses.fold<int>(0, (m, e) => e.total > m ? e.total : m);

        return RefreshIndicator(
          onRefresh: _recargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _IndicadoresAhora(resumen: resumen, onVerHoy: () => _abrirMes(ahora.month)),
              const SizedBox(height: 24),
              TituloSeccion(
                "Por mes",
                accion: _SelectorAnio(
                  anio: resumen.anio,
                  puedeAvanzar: !esAnioActual,
                  onCambiar: _cambiarAnio,
                ),
              ),
              const SizedBox(height: 4),
              _ResumenAnio(resumen: resumen, esAnioActual: esAnioActual),
              const SizedBox(height: 12),
              for (final mesInfo in resumen.meses) ...[
                _FilaMes(
                  nombre: nombresMesEs[mesInfo.mes - 1],
                  info: mesInfo,
                  maximo: maximoMes,
                  esActual: esAnioActual && mesInfo.mes == ahora.month,
                  esFuturo: esAnioActual && mesInfo.mes > ahora.month ||
                      resumen.anio > ahora.year,
                  onTap: () => _abrirMes(mesInfo.mes),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _IndicadoresAhora extends StatelessWidget {
  const _IndicadoresAhora({required this.resumen, required this.onVerHoy});

  final BitacoraResumenAnio resumen;
  final VoidCallback onVerHoy;

  @override
  Widget build(BuildContext context) {
    final hayAbiertos = resumen.abiertosAhora > 0;
    return Row(
      children: [
        Expanded(
          child: IndicadorTile(
            etiqueta: "Abiertos",
            valor: "${resumen.abiertosAhora}",
            icono: hayAbiertos ? Icons.error_outline : Icons.check_circle_outline,
            color: hayAbiertos ? StatusColors.critico : StatusColors.exitoso,
            onTap: onVerHoy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: IndicadorTile(
            etiqueta: "Hoy",
            valor: "${resumen.hoy}",
            icono: Icons.today_outlined,
            onTap: onVerHoy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: IndicadorTile(
            etiqueta: "7 días",
            valor: "${resumen.ultimos7Dias}",
            icono: Icons.date_range_outlined,
          ),
        ),
      ],
    );
  }
}

class _ResumenAnio extends StatelessWidget {
  const _ResumenAnio({required this.resumen, required this.esAnioActual});

  final BitacoraResumenAnio resumen;
  final bool esAnioActual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final variacion = resumen.variacionPct;
    final sube = variacion != null && variacion >= 0;
    return Row(
      children: [
        Text(
          "${_formatearMiles(resumen.totalAnual)} episodios en ${resumen.anio}"
          "${esAnioActual ? ' hasta hoy' : ''}",
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (variacion != null) ...[
          const SizedBox(width: 8),
          Icon(
            sube ? Icons.trending_up : Icons.trending_down,
            size: 14,
            color: sube ? StatusColors.critico : StatusColors.exitoso,
          ),
          const SizedBox(width: 2),
          Text(
            "${sube ? '+' : ''}$variacion% vs ${resumen.anio - 1}",
            style: theme.textTheme.bodySmall?.copyWith(
              color: sube ? StatusColors.critico : StatusColors.exitoso,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _SelectorAnio extends StatelessWidget {
  const _SelectorAnio({
    required this.anio,
    required this.puedeAvanzar,
    required this.onCambiar,
  });

  final int anio;
  final bool puedeAvanzar;
  final void Function(int delta) onCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onCambiar(-1),
          icon: const Icon(Icons.chevron_left),
          tooltip: "Año anterior",
        ),
        Text(
          "$anio",
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: puedeAvanzar ? () => onCambiar(1) : null,
          icon: const Icon(Icons.chevron_right),
          tooltip: "Año siguiente",
        ),
      ],
    );
  }
}

/// Una fila por mes: nombre, barra proporcional al mes con más episodios,
/// total y cuántos siguen abiertos. Reemplaza a la grilla de 12 cuadrados
/// con un punto de color, que no decía cuánto ni qué quedaba pendiente.
class _FilaMes extends StatelessWidget {
  const _FilaMes({
    required this.nombre,
    required this.info,
    required this.maximo,
    required this.esActual,
    required this.esFuturo,
    required this.onTap,
  });

  final String nombre;
  final BitacoraResumenMes info;
  final int maximo;
  final bool esActual;
  final bool esFuturo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sinDatos = info.total == 0;
    final proporcion = maximo == 0 ? 0.0 : info.total / maximo;
    final colorBarra = info.abiertos > 0
        ? StatusColors.critico
        : sinDatos
            ? colorScheme.outlineVariant
            : colorScheme.primary;
    final colorTexto = esFuturo
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
        : colorScheme.onSurface;

    return Material(
      color: esActual
          ? colorScheme.primary.withValues(alpha: 0.10)
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: esFuturo ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  nombre,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorTexto,
                    fontWeight: esActual ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: proporcion,
                    minHeight: 8,
                    backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.35),
                    color: colorBarra,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 58,
                child: Text(
                  sinDatos ? "–" : _formatearMiles(info.total),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorTexto,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 54,
                child: info.abiertos > 0
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: StatusColors.critico.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "${info.abiertos}",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: StatusColors.critico,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    : Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: esFuturo
                            ? Colors.transparent
                            : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatearMiles(int n) {
  final texto = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < texto.length; i++) {
    final restantes = texto.length - i;
    buffer.write(texto[i]);
    if (restantes > 1 && restantes % 3 == 1) buffer.write(".");
  }
  return buffer.toString();
}
