import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../utils/meses_es.dart";
import "../widgets/estado_vacio.dart";
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
      builder: (_) => _FormularioEntrada(anio: widget.anio, mes: widget.mes),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
            "${nombresMesEs[widget.mes - 1].toUpperCase()} ${widget.anio}"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirFormulario,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<BitacoraError>>(
        future: _entradasFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EstadoVacio(
              icono: Icons.error_outline,
              mensaje: "No se pudieron cargar las entradas.",
              colorIcono: colorScheme.error,
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
          final uptimePct = diasTranscurridos == 0
              ? 100.0
              : (diasTranscurridos - diasConError) / diasTranscurridos * 100;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              _Calendario(
                anio: widget.anio,
                mes: widget.mes,
                porDia: porDia,
                onTocarDia: _abrirDia,
              ),
              const SizedBox(height: 24),
              Text(
                "ESTADÍSTICAS OPERATIVAS",
                style: AppTextStyles.tech(
                    color: colorScheme.primary, fontSize: 10),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: StatusColors.critico.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.bar_chart, color: StatusColors.critico),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Resumen del Mes",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 13),
                              children: [
                                TextSpan(
                                  text:
                                      "${entradas.length} error${entradas.length == 1 ? '' : 'es'} ",
                                  style: TextStyle(
                                      color: StatusColors.critico,
                                      fontWeight: FontWeight.bold),
                                ),
                                const TextSpan(
                                    text: "detectados en el periodo actual."),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _CasillaStat(
                      titulo: "UPTIME",
                      valor: "${uptimePct.toStringAsFixed(1)}%",
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CasillaStat(
                      titulo: "CRITICAL",
                      valor: diasConError.toString().padLeft(2, "0"),
                      color: StatusColors.critico,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: 128,
                      height: 128,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: uptimePct / 100),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, valor, _) => Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: valor,
                              strokeWidth: 8,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              valueColor:
                                  AlwaysStoppedAnimation(colorScheme.primary),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("${(valor * 100).round()}%",
                                    style: AppTextStyles.tech(
                                        color: colorScheme.onSurface,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                Text("SALUD",
                                    style: AppTextStyles.tech(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 9)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      uptimePct >= 90
                          ? "Nivel de eficiencia estable para el periodo de ${nombresMesEs[widget.mes - 1]}."
                          : "Eficiencia por debajo de lo esperado en ${nombresMesEs[widget.mes - 1]}: revisar procesos.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
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

class _CasillaStat extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color color;

  const _CasillaStat(
      {required this.titulo, required this.valor, required this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: AppTextStyles.tech(
                  color: colorScheme.onSurfaceVariant, fontSize: 10)),
          const SizedBox(height: 4),
          Text(valor,
              style: AppTextStyles.tech(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: _diasSemana
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d,
                          style: AppTextStyles.tech(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: celdas,
          ),
        ),
      ],
    );
  }

  Widget _celdaOpaca(int dia) {
    return Center(
      child: Opacity(
        opacity: 0.2,
        child: Text("$dia",
            style: AppTextStyles.tech(
                fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w400)),
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
    Widget contenido = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: esHoy ? colorScheme.primary : Colors.transparent,
        border: !esHoy && tieneError
            ? Border.all(color: StatusColors.critico)
            : null,
        boxShadow: esHoy
            ? [
                BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.4),
                    blurRadius: 12)
              ]
            : tieneError
                ? [
                    BoxShadow(
                        color: StatusColors.critico.withValues(alpha: 0.3),
                        blurRadius: 10)
                  ]
                : null,
      ),
      child: Text(
        "$dia",
        style: AppTextStyles.tech(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: esHoy
              ? colorScheme.onPrimary
              : tieneError
                  ? StatusColors.critico
                  : colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: tieneError ? () => onTocarDia(dia, entradasDelDia!) : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          contenido,
          const SizedBox(height: 2),
          if (tieneError && !esHoy)
            Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: StatusColors.critico))
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _FormularioEntrada extends StatefulWidget {
  final int anio;
  final int mes;

  const _FormularioEntrada({required this.anio, required this.mes});

  @override
  State<_FormularioEntrada> createState() => _FormularioEntradaState();
}

class _FormularioEntradaState extends State<_FormularioEntrada> {
  final _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  bool _esProceso = true;
  String _tecnologia = tecnologiasProceso.first;
  String _estado = estadosProceso.first;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _apiService.crearEntradaBitacora(
        nombre: _nombreController.text.trim(),
        tecnologia: _tecnologia,
        estado: _estado,
        descripcion: _descripcionController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final opciones = _esProceso ? tecnologiasProceso : tecnologiasTabla;
    final opcionesEstado = _esProceso ? estadosProceso : estadosTabla;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text("Registrar error",
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text("Proceso")),
                  ButtonSegment(value: false, label: Text("Tabla")),
                ],
                selected: {_esProceso},
                onSelectionChanged: (seleccion) => setState(() {
                  _esProceso = seleccion.first;
                  _tecnologia = opciones.first;
                  _estado = (_esProceso ? estadosProceso : estadosTabla).first;
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _tecnologia,
                decoration: const InputDecoration(labelText: "Tecnología"),
                items: opciones
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (valor) => setState(() => _tecnologia = valor!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _estado,
                decoration: const InputDecoration(labelText: "Estado"),
                items: opcionesEstado
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (valor) => setState(() => _estado = valor!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombreController,
                decoration: InputDecoration(
                    labelText: _esProceso
                        ? "Nombre del proceso"
                        : "Nombre de la tabla"),
                validator: (valor) =>
                    (valor?.trim().isEmpty ?? true) ? "Obligatorio" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: "Descripción",
                  hintText: _esProceso
                      ? "Por qué falló el proceso..."
                      : "¿Tabla vacía? ¿Cuenta con datos incorrectos?...",
                ),
                validator: (valor) =>
                    (valor?.trim().isEmpty ?? true) ? "Obligatorio" : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: TextStyle(color: colorScheme.error, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Guardar"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
