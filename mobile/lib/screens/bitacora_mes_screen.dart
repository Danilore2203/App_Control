import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "../utils/meses_es.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/fondo_app.dart";
import "../widgets/formulario_entrada_bitacora.dart";
import "../widgets/titulo_seccion.dart";
import "bitacora_dia_screen.dart";

const _diasSemana = ["L", "M", "X", "J", "V", "S", "D"];

class BitacoraMesScreen extends StatefulWidget {
  final int anio;
  final int mes;

  const BitacoraMesScreen({super.key, required this.anio, required this.mes});

  @override
  State<BitacoraMesScreen> createState() => _BitacoraMesScreenState();
}

class _BitacoraMesScreenState extends State<BitacoraMesScreen> {
  final _apiService = ApiService();
  late Future<List<BitacoraError>> _entradasFuture;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _entradasFuture =
        _apiService.obtenerBitacoraEntradas(widget.anio, mes: widget.mes);
  }

  Future<void> _abrirFormulario() async {
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FormularioEntradaBitacora(),
    );
    if (creado == true) setState(_cargar);
  }

  Future<void> _abrirDia(int dia, List<BitacoraError> entradasDelDia) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BitacoraDiaScreen(
          anio: widget.anio,
          mes: widget.mes,
          dia: dia,
          entradasIniciales: entradasDelDia,
        ),
      ),
    );
    setState(_cargar);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Eyebrow("Bitácora ${widget.anio}"),
            Text(nombresMesEs[widget.mes - 1]),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        icon: const Icon(Icons.add_rounded),
        label: const Text("Registrar"),
      ),
      body: FutureBuilder<List<BitacoraError>>(
        future: _entradasFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EstadoVacio(
              icono: Icons.cloud_off_rounded,
              mensaje: "No se pudieron cargar las entradas",
              colorIcono: colorScheme.error,
              onReintentar: () async => setState(_cargar),
            );
          }

          final entradas = snapshot.data ?? [];
          final porDia = <int, List<BitacoraError>>{};
          for (final entrada in entradas) {
            porDia.putIfAbsent(entrada.fechaHora.day, () => []).add(entrada);
          }

          final ahora = DateTime.now();
          final esMesActual =
              widget.anio == ahora.year && widget.mes == ahora.month;
          final diasEnMes = DateTime(widget.anio, widget.mes + 1, 0).day;
          final diasTranscurridos = esMesActual ? ahora.day : diasEnMes;
          final diasConError =
              porDia.keys.where((d) => d <= diasTranscurridos).length;
          final abiertos = entradas.where((e) => !e.resuelto).length;
          final resueltos = entradas.length - abiertos;
          final procesos = entradas.where((e) => e.esProceso).length;
          final tablas = entradas.length - procesos;
          final diaPico = porDia.entries.fold<MapEntry<int, List<BitacoraError>>?>(
            null,
            (max, e) => max == null || e.value.length > max.value.length ? e : max,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              Row(
                children: [
                  Expanded(
                    child: IndicadorTile(
                      etiqueta: "Episodios",
                      valor: formatearMiles(entradas.length),
                      icono: Icons.list_alt_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IndicadorTile(
                      etiqueta: "Abiertos",
                      valor: formatearMiles(abiertos),
                      icono: abiertos > 0 ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      color: abiertos > 0 ? StatusColors.critico : StatusColors.exitoso,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IndicadorTile(
                      etiqueta: "Resueltos",
                      valor: formatearMiles(resueltos),
                      icono: Icons.task_alt_rounded,
                      color: StatusColors.exitoso,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TituloSeccion(
                "Calendario",
                accion: Text(
                  "$diasConError de $diasTranscurridos días con fallas",
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                ),
              ),
              const SizedBox(height: 10),
              _Calendario(
                anio: widget.anio,
                mes: widget.mes,
                porDia: porDia,
                onTocarDia: _abrirDia,
              ),
              const SizedBox(height: 22),
              const TituloSeccion("Resumen del mes"),
              const SizedBox(height: 10),
              Vidrio(
                padding: const EdgeInsets.all(16),
                blur: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FilaResumen(
                      etiqueta: "Procesos",
                      valor: procesos,
                      total: entradas.length,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    _FilaResumen(
                      etiqueta: "Tablas",
                      valor: tablas,
                      total: entradas.length,
                      color: StatusColors.info,
                    ),
                    const SizedBox(height: 12),
                    _FilaResumen(
                      etiqueta: "Siguen abiertos",
                      valor: abiertos,
                      total: entradas.length,
                      color: StatusColors.critico,
                    ),
                    if (diaPico != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.trending_up_rounded, size: 16, color: colorScheme.outline),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Día con más episodios: ${diaPico.key} de ${nombresMesEs[widget.mes - 1]} (${formatearMiles(diaPico.value.length)})",
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilaResumen extends StatelessWidget {
  const _FilaResumen({required this.etiqueta, required this.valor, required this.total, required this.color});

  final String etiqueta;
  final int valor;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(etiqueta, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              formatearMiles(valor),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        BarraProgreso(valor: total == 0 ? 0 : valor / total, color: color),
      ],
    );
  }
}

class _Calendario extends StatelessWidget {
  final int anio;
  final int mes;
  final Map<int, List<BitacoraError>> porDia;
  final void Function(int dia, List<BitacoraError> entradas) onTocarDia;

  const _Calendario({
    required this.anio,
    required this.mes,
    required this.porDia,
    required this.onTocarDia,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ahora = DateTime.now();
    final esMesActual = anio == ahora.year && mes == ahora.month;

    final diasEnMes = DateTime(anio, mes + 1, 0).day;
    final offsetInicio = DateTime(anio, mes, 1).weekday - 1; // 0 = lunes
    final mesAnterior = mes == 1 ? 12 : mes - 1;
    final anioMesAnterior = mes == 1 ? anio - 1 : anio;
    final diasMesAnterior = DateTime(anioMesAnterior, mesAnterior + 1, 0).day;

    final celdas = <Widget>[];

    for (var i = 0; i < offsetInicio; i++) {
      final dia = diasMesAnterior - offsetInicio + i + 1;
      celdas.add(_celdaOpaca(dia));
    }

    for (var dia = 1; dia <= diasEnMes; dia++) {
      final entradasDelDia = porDia[dia];
      final tieneError = entradasDelDia != null && entradasDelDia.isNotEmpty;
      final esHoy = esMesActual && dia == ahora.day;

      celdas.add(_celdaDia(
          context, dia, tieneError, esHoy, entradasDelDia, colorScheme));
    }

    var relleno = 1;
    while (celdas.length % 7 != 0) {
      celdas.add(_celdaOpaca(relleno));
      relleno++;
    }

    return Vidrio(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      blur: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: _diasSemana
                .map((d) => Expanded(child: Center(child: Eyebrow(d))))
                .toList(),
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.92,
            children: celdas,
          ),
        ],
      ),
    );
  }

  Widget _celdaOpaca(int dia) {
    return Builder(
      builder: (context) => Center(
        child: Text(
          "$dia",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  Widget _celdaDia(
    BuildContext context,
    int dia,
    bool tieneError,
    bool esHoy,
    List<BitacoraError>? entradasDelDia,
    ColorScheme colorScheme,
  ) {
    final theme = Theme.of(context);
    final cantidad = entradasDelDia?.length ?? 0;
    final hayAbiertos = entradasDelDia?.any((e) => !e.resuelto) ?? false;
    final tono = hayAbiertos ? StatusColors.critico : StatusColors.exitoso;

    final Color fondo;
    final Color colorTexto;
    final Border? borde;
    if (esHoy) {
      fondo = colorScheme.primary;
      colorTexto = colorScheme.onPrimary;
      borde = null;
    } else if (tieneError) {
      fondo = tono.withValues(alpha: 0.14);
      colorTexto = tono;
      borde = Border.all(color: tono.withValues(alpha: 0.45));
    } else {
      fondo = Colors.transparent;
      colorTexto = colorScheme.onSurfaceVariant;
      borde = null;
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: tieneError ? () => onTocarDia(dia, entradasDelDia!) : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: borde,
              boxShadow: esHoy
                  ? [BoxShadow(color: colorScheme.primary.withValues(alpha: 0.35), blurRadius: 12)]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "$dia",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorTexto,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                if (tieneError)
                  Text(
                    "$cantidad",
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: esHoy ? colorScheme.onPrimary.withValues(alpha: 0.8) : tono,
                    ),
                  )
                else
                  const SizedBox(height: 11),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

