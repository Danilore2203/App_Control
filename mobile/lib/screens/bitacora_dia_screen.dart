import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../utils/meses_es.dart";
import "../widgets/estado_vacio.dart";

IconData iconoTecnologia(String tecnologia) {
  switch (tecnologia) {
    case "AIRFLOW":
      return Icons.account_tree_outlined;
    case "DATASTAGE":
      return Icons.dns_outlined;
    case "PENTAHO":
      return Icons.hub_outlined;
    case "QA_CONTROL":
      return Icons.fact_check_outlined;
    case "PG_PROD":
      return Icons.storage_outlined;
    default:
      return Icons.memory;
  }
}

/// Color de acento por tecnologia (paleta "VIVA Operational Control").
Color colorTecnologia(String tecnologia) {
  switch (tecnologia) {
    case "AIRFLOW":
      return const Color(0xFF007AFF);
    case "DATASTAGE":
      return const Color(0xFFFFD60A);
    case "PENTAHO":
      return const Color(0xFF30D158);
    case "QA_CONTROL":
      return const Color(0xFFAF52DE);
    case "PG_PROD":
      return const Color(0xFFFF9F0A);
    default:
      return const Color(0xFF90937B);
  }
}

/// Detalle de un dia especifico de la bitacora: fallos reales (con su
/// descripcion real, no inventada) ocurridos ese dia.
class BitacoraDiaScreen extends StatefulWidget {
  final int anio;
  final int mes;
  final int dia;
  final List<BitacoraError> entradasIniciales;

  const BitacoraDiaScreen({
    super.key,
    required this.anio,
    required this.mes,
    required this.dia,
    required this.entradasIniciales,
  });

  @override
  State<BitacoraDiaScreen> createState() => _BitacoraDiaScreenState();
}

class _BitacoraDiaScreenState extends State<BitacoraDiaScreen>
    with SingleTickerProviderStateMixin {
  final _apiService = ApiService();
  late List<BitacoraError> _entradas;
  final _busquedaController = TextEditingController();
  String _busqueda = "";
  String? _filtroEstado; // null=todos, "ERROR"=abiertos, "OK"=resueltos
  bool? _filtroEsProceso; // null=todos, true=procesos, false=tablas
  String? _filtroTecnologia;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _entradas = widget.entradasIniciales;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _abrirFormulario() async {
    final ahora = DateTime.now();
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormularioEntradaDia(
        fechaHora: DateTime(
            widget.anio, widget.mes, widget.dia, ahora.hour, ahora.minute),
      ),
    );
    if (creado == true) {
      final nuevasEntradas = await _apiService
          .obtenerBitacoraEntradas(widget.anio, mes: widget.mes);
      setState(() {
        _entradas =
            nuevasEntradas.where((e) => e.fechaHora.day == widget.dia).toList();
      });
    }
  }

  List<String> get _tecnologiasAfectadas =>
      _entradas.map((e) => e.tecnologia).toSet().toList();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final busquedaLimpia = _busqueda.trim().toLowerCase();
    final abiertos = _entradas.where((e) => !e.resuelto).length;
    final resueltos = _entradas.where((e) => e.resuelto).length;
    final procesos = _entradas.where((e) => e.esProceso).length;
    final tablas = _entradas.length - procesos;
    final entradasFiltradas = _entradas.where((e) {
      final coincideBusqueda = busquedaLimpia.isEmpty ||
          e.nombre.toLowerCase().contains(busquedaLimpia) ||
          e.tecnologia.toLowerCase().contains(busquedaLimpia);
      final coincideEstado = _filtroEstado == null ||
          (_filtroEstado == "OK" ? e.resuelto : !e.resuelto);
      final coincideTipo =
          _filtroEsProceso == null || e.esProceso == _filtroEsProceso;
      final coincideTecnologia =
          _filtroTecnologia == null || e.tecnologia == _filtroTecnologia;
      return coincideBusqueda &&
          coincideEstado &&
          coincideTipo &&
          coincideTecnologia;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
            "${widget.dia} DE ${nombresMesEs[widget.mes - 1].toUpperCase()}"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _abrirFormulario,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border(
                  left: BorderSide(
                      color: abiertos > 0
                          ? StatusColors.critico
                          : StatusColors.exitoso,
                      width: 4)),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -10,
                  right: -10,
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 90,
                    color: (abiertos > 0
                            ? StatusColors.critico
                            : StatusColors.exitoso)
                        .withValues(alpha: 0.08),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) => Opacity(
                        opacity: abiertos > 0
                            ? 0.6 + (_pulseController.value * 0.4)
                            : 1,
                        child: child,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: abiertos > 0
                              ? StatusColors.critico
                              : StatusColors.exitoso,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                abiertos > 0
                                    ? Icons.error_outline
                                    : Icons.check_circle_outline,
                                color: Colors.white,
                                size: 14),
                            const SizedBox(width: 6),
                            Text(
                              abiertos > 0
                                  ? "$abiertos FALLO${abiertos == 1 ? '' : 'S'} CRÍTICO${abiertos == 1 ? '' : 'S'}"
                                  : "SIN FALLOS ABIERTOS",
                              style: AppTextStyles.tech(
                                  color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text("Resumen Operativo",
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      _tecnologiasAfectadas.isEmpty
                          ? "Sin fallos registrados este día."
                          : "Se detectaron fallos en: ${_tecnologiasAfectadas.join(', ')}.",
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _busquedaController,
            onChanged: (valor) => setState(() => _busqueda = valor),
            decoration: InputDecoration(
              hintText: "Buscar proceso o tabla...",
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _busquedaController.clear();
                        setState(() => _busqueda = "");
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ChipEstado(
                  etiqueta: "TODOS",
                  cantidad: _entradas.length,
                  color: colorScheme.primary,
                  seleccionado: _filtroEstado == null,
                  onTap: () => setState(() => _filtroEstado = null),
                ),
                const SizedBox(width: 8),
                _ChipEstado(
                  etiqueta: "ABIERTOS",
                  cantidad: abiertos,
                  color: StatusColors.critico,
                  seleccionado: _filtroEstado == "ERROR",
                  onTap: () => setState(() => _filtroEstado = "ERROR"),
                ),
                const SizedBox(width: 8),
                _ChipEstado(
                  etiqueta: "RESUELTOS",
                  cantidad: resueltos,
                  color: StatusColors.exitoso,
                  seleccionado: _filtroEstado == "OK",
                  onTap: () => setState(() => _filtroEstado = "OK"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ChipEstado(
                  etiqueta: "TODOS",
                  cantidad: _entradas.length,
                  color: colorScheme.primary,
                  seleccionado: _filtroEsProceso == null,
                  onTap: () => setState(() => _filtroEsProceso = null),
                ),
                const SizedBox(width: 8),
                _ChipEstado(
                  etiqueta: "PROCESOS",
                  cantidad: procesos,
                  color: StatusColors.info,
                  seleccionado: _filtroEsProceso == true,
                  onTap: () => setState(() => _filtroEsProceso = true),
                ),
                const SizedBox(width: 8),
                _ChipEstado(
                  etiqueta: "TABLAS",
                  cantidad: tablas,
                  color: StatusColors.advertencia,
                  seleccionado: _filtroEsProceso == false,
                  onTap: () => setState(() => _filtroEsProceso = false),
                ),
              ],
            ),
          ),
          if (_tecnologiasAfectadas.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final tecnologia in _tecnologiasAfectadas) ...[
                    _ChipTecnologia(
                      tecnologia: tecnologia,
                      seleccionado: _filtroTecnologia == tecnologia,
                      onTap: () => setState(() => _filtroTecnologia =
                          _filtroTecnologia == tecnologia ? null : tecnologia),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (entradasFiltradas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EstadoVacio(
                icono: Icons.check_circle_outline,
                mensaje: _entradas.isEmpty
                    ? "Sin fallos registrados este día"
                    : "Sin resultados para tu búsqueda",
                colorIcono: colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final entrada in entradasFiltradas)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _TarjetaFalloDia(entrada: entrada),
              ),
        ],
      ),
    );
  }
}

class _ChipEstado extends StatelessWidget {
  final String etiqueta;
  final int cantidad;
  final Color color;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipEstado({
    required this.etiqueta,
    required this.cantidad,
    required this.color,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: seleccionado ? color : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: seleccionado
                  ? Colors.transparent
                  : colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(etiqueta,
                style: AppTextStyles.tech(
                    color: seleccionado ? colorScheme.onPrimary : color,
                    fontSize: 10)),
            const SizedBox(width: 6),
            Text("$cantidad",
                style: AppTextStyles.tech(
                    color: (seleccionado ? colorScheme.onPrimary : color)
                        .withValues(alpha: 0.8),
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _ChipTecnologia extends StatelessWidget {
  final String tecnologia;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipTecnologia({
    required this.tecnologia,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorTecnologia(tecnologia);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: seleccionado ? 0.9 : 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconoTecnologia(tecnologia),
                size: 14, color: seleccionado ? Colors.white : color),
            const SizedBox(width: 6),
            Text(tecnologia,
                style: AppTextStyles.tech(
                    color: seleccionado ? Colors.white : color,
                    fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class _TarjetaFalloDia extends StatelessWidget {
  final BitacoraError entrada;

  const _TarjetaFalloDia({required this.entrada});

  String _hora(DateTime fecha) =>
      "${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resuelto = entrada.resuelto;
    final color = resuelto ? StatusColors.exitoso : StatusColors.critico;
    final colorTech = colorTecnologia(entrada.tecnologia);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 16)
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorTech.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconoTecnologia(entrada.tecnologia),
                    color: colorTech, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "${entrada.tecnologia} · ${entrada.estado ?? (entrada.esProceso ? 'ERROR' : 'TABLA')}",
                            style: AppTextStyles.tech(
                                color: colorTech, fontSize: 9),
                          ),
                        ),
                        if (resuelto)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: StatusColors.exitoso
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text("RESUELTO",
                                style: AppTextStyles.tech(
                                    color: StatusColors.exitoso, fontSize: 8)),
                          ),
                      ],
                    ),
                    Text(
                      entrada.nombre,
                      style: AppTextStyles.tech(
                          color: colorScheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                _hora(entrada.fechaHora),
                style: AppTextStyles.tech(
                    color: colorScheme.onSurfaceVariant, fontSize: 10),
              ),
            ],
          ),
          if (entrada.fechaActualizacion != null &&
              entrada.fechaActualizacion!
                      .difference(entrada.fechaHora)
                      .inMinutes
                      .abs() >=
                  1) ...[
            const SizedBox(height: 4),
            Text(
              "Última lectura: ${_hora(entrada.fechaActualizacion!)}",
              style: TextStyle(
                  color: colorScheme.onSurfaceVariant, fontSize: 10.5),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                    resuelto
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: color,
                    size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entrada.descripcion,
                    style:
                        TextStyle(color: color, fontSize: 12.5, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormularioEntradaDia extends StatefulWidget {
  final DateTime fechaHora;

  const _FormularioEntradaDia({required this.fechaHora});

  @override
  State<_FormularioEntradaDia> createState() => _FormularioEntradaDiaState();
}

class _FormularioEntradaDiaState extends State<_FormularioEntradaDia> {
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
        fechaHora: widget.fechaHora,
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
              Text(
                  "Registrar error · ${widget.fechaHora.day} DE ${nombresMesEs[widget.fechaHora.month - 1].toUpperCase()}",
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
