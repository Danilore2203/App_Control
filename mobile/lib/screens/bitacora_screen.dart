import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/actualizaciones_service.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "../utils/meses_es.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/fondo_app.dart";
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
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 12,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.18,
                ),
                itemBuilder: (context, index) {
                  final mesInfo = resumen.meses[index];
                  return _TarjetaMes(
                    nombre: mesesAbrevEs[index],
                    info: mesInfo,
                    maximo: maximoMes,
                    esActual: esAnioActual && mesInfo.mes == ahora.month,
                    esFuturo: esAnioActual && mesInfo.mes > ahora.month ||
                        resumen.anio > ahora.year,
                    onTap: () => _abrirMes(mesInfo.mes),
                  );
                },
              ),
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
          "${formatearMiles(resumen.totalAnual)} episodios en ${resumen.anio}"
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

/// Cuadro de un mes: nombre, total grande, barra proporcional al mes con
/// más episodios y badge con los que siguen abiertos. El mes actual va
/// resaltado en lima; los futuros, atenuados y sin acción.
class _TarjetaMes extends StatelessWidget {
  const _TarjetaMes({
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
    final proporcion = maximo == 0 ? 0.0 : (info.total / maximo).clamp(0.04, 1.0);
    final hayAbiertos = info.abiertos > 0;
    final colorBarra = hayAbiertos
        ? StatusColors.critico
        : sinDatos
            ? Colors.transparent
            : colorScheme.primary;
    final colorTexto = esFuturo
        ? colorScheme.outline.withValues(alpha: 0.5)
        : colorScheme.onSurface;
    // Tono de la tarjeta (linea superior, como .lt-kpi::after): rojo si
    // quedan abiertos, lima si es el mes actual, neutro si no.
    final tono = hayAbiertos
        ? StatusColors.critico
        : esActual
            ? colorScheme.primary
            : colorScheme.outlineVariant;

    return Vidrio(
      padding: EdgeInsets.zero,
      blur: 10,
      color: esActual ? colorScheme.primary.withValues(alpha: 0.14) : null,
      borderColor: esActual
          ? colorScheme.primary.withValues(alpha: 0.6)
          : hayAbiertos
              ? StatusColors.critico.withValues(alpha: 0.35)
              : null,
      onTap: esFuturo ? null : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: esFuturo ? Colors.transparent : tono),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Eyebrow(
                        nombre,
                        color: esActual ? acentoTinta(context) : (esFuturo ? colorTexto : null),
                      ),
                      if (hayAbiertos)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: StatusColors.critico,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            "${info.abiertos}",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    sinDatos ? "–" : formatearMiles(info.total),
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: sinDatos ? colorScheme.outline.withValues(alpha: 0.5) : colorTexto,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: sinDatos ? 0 : proporcion,
                      minHeight: 4,
                      backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      color: colorBarra,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

