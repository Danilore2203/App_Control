import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../widgets/estado_vacio.dart";
import "bitacora_mes_screen.dart";

const _mesesAbrev = [
  "ENE",
  "FEB",
  "MAR",
  "ABR",
  "MAY",
  "JUN",
  "JUL",
  "AGO",
  "SEP",
  "OCT",
  "NOV",
  "DIC",
];

/// Bitacora de errores: registro manual de fallas de procesos (AIRFLOW,
/// DATASTAGE, PENTAHO) y de tablas (QA_CONTROL, PG_PROD), agrupado por mes.
class BitacoraScreen extends StatefulWidget {
  const BitacoraScreen({super.key});

  @override
  State<BitacoraScreen> createState() => _BitacoraScreenState();
}

class _BitacoraScreenState extends State<BitacoraScreen> {
  final _apiService = ApiService();
  late int _anio;
  late Future<BitacoraResumenAnio> _resumenFuture;

  @override
  void initState() {
    super.initState();
    _anio = DateTime.now().year;
    _cargar();
  }

  void _cargar() {
    _resumenFuture = _apiService.obtenerBitacoraResumen(_anio);
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
    setState(_cargar);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ahora = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text("BITÁCORA",
            style:
                AppTextStyles.tech(color: colorScheme.onSurface, fontSize: 14)),
      ),
      body: FutureBuilder<BitacoraResumenAnio>(
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
            );
          }

          final resumen = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "PERIODO ACTUAL",
                        style: AppTextStyles.tech(
                            color: colorScheme.onSurfaceVariant, fontSize: 10),
                      ),
                      Text(
                        "${resumen.anio}",
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton.outlined(
                        onPressed: () => _cambiarAnio(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        onPressed: resumen.anio >= ahora.year
                            ? null
                            : () => _cambiarAnio(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "TOTAL ERRORES ${resumen.anio == ahora.year ? 'YTD' : ''}",
                          style: AppTextStyles.tech(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10),
                        ),
                        Text(
                          "${resumen.totalAnual}",
                          style: AppTextStyles.tech(
                              color: colorScheme.primary,
                              fontSize: 26,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (resumen.variacionPct != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (resumen.variacionPct! >= 0
                                      ? StatusColors.critico
                                      : StatusColors.exitoso)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  resumen.variacionPct! >= 0
                                      ? Icons.trending_up
                                      : Icons.trending_down,
                                  size: 14,
                                  color: resumen.variacionPct! >= 0
                                      ? StatusColors.critico
                                      : StatusColors.exitoso,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  "${resumen.variacionPct! >= 0 ? '+' : ''}${resumen.variacionPct}%",
                                  style: TextStyle(
                                    color: resumen.variacionPct! >= 0
                                        ? StatusColors.critico
                                        : StatusColors.exitoso,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text("vs ${resumen.anio - 1}",
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11)),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "BITÁCORA MENSUAL",
                style: AppTextStyles.tech(
                    color: colorScheme.onSurfaceVariant, fontSize: 10),
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 12,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.95,
                ),
                itemBuilder: (context, index) {
                  final mesInfo = resumen.meses[index];
                  final esHoy =
                      resumen.anio == ahora.year && mesInfo.mes == ahora.month;
                  return _TarjetaMes(
                    etiqueta: _mesesAbrev[index],
                    tieneError: mesInfo.tieneError,
                    total: mesInfo.total,
                    esHoy: esHoy,
                    onTap: () => _abrirMes(mesInfo.mes),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TarjetaMes extends StatelessWidget {
  final String etiqueta;
  final bool tieneError;
  final int total;
  final bool esHoy;
  final VoidCallback onTap;

  const _TarjetaMes({
    required this.etiqueta,
    required this.tieneError,
    required this.total,
    required this.esHoy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = esHoy
        ? colorScheme.primary
        : tieneError
            ? StatusColors.critico
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return Material(
      color: esHoy
          ? colorScheme.primary.withValues(alpha: 0.1)
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: esHoy
                  ? colorScheme.primary.withValues(alpha: 0.4)
                  : tieneError
                      ? StatusColors.critico.withValues(alpha: 0.35)
                      : Colors.transparent,
            ),
          ),
          child: Stack(
            children: [
              if (tieneError && !esHoy)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Text("!",
                      style: TextStyle(
                          color: StatusColors.critico,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      etiqueta,
                      style: AppTextStyles.tech(
                        color:
                            esHoy ? colorScheme.primary : colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: color),
                    ),
                  ],
                ),
              ),
              if (esHoy)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      "HOY",
                      style: AppTextStyles.tech(
                          color: colorScheme.primary.withValues(alpha: 0.7),
                          fontSize: 8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
