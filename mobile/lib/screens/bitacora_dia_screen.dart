import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../utils/meses_es.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/formulario_entrada_bitacora.dart";

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

/// Ícono según el tipo de evento (estado crudo de la fila), no según la
/// tecnología - ERROR/INCOHERENCIA/VACIA/DATOS_INCORRECTOS comparten ícono
/// de fallo, cada categoría nueva tiene el suyo.
IconData iconoEvento(BitacoraError entrada) {
  if (entrada.resuelto) return Icons.check_circle_outline;
  switch ((entrada.estado ?? "").toUpperCase()) {
    case "DEMORADO":
      return Icons.schedule;
    case "EJECUTADO":
      return Icons.play_circle_outline;
    case "ADVERTENCIA":
      return Icons.warning_amber_rounded;
    case "INFORMACION":
      return Icons.info_outline;
    case "REINTENTO":
      return Icons.refresh;
    default:
      return Icons.error_outline;
  }
}

/// Color según el tipo de evento: ERROR=rojo, RESUELTO=verde, DEMORADO=
/// amarillo, EJECUTADO=azul, ADVERTENCIA=naranja, INFORMACIÓN=gris.
Color colorEvento(BitacoraError entrada) {
  if (entrada.resuelto) return StatusColors.exitoso;
  switch ((entrada.estado ?? "").toUpperCase()) {
    case "DEMORADO":
      return StatusColors.demorado;
    case "EJECUTADO":
      return StatusColors.info;
    case "ADVERTENCIA":
      return StatusColors.advertencia;
    case "INFORMACION":
      return StatusColors.neutral;
    case "REINTENTO":
      return StatusColors.info;
    default:
      return StatusColors.critico;
  }
}

/// Etiqueta legible por categoría de filtro (Todos/Errores/Resueltos/
/// Demorados/Ejecutados/Información), en el mismo orden que pidió el
/// usuario.
const _categoriasFiltro = ["ERROR", "RESUELTO", "DEMORADO", "EJECUTADO", "INFORMACION"];

String etiquetaCategoria(String categoria) {
  switch (categoria) {
    case "ERROR":
      return "ERRORES";
    case "RESUELTO":
      return "RESUELTOS";
    case "DEMORADO":
      return "DEMORADOS";
    case "EJECUTADO":
      return "EJECUTADOS";
    case "INFORMACION":
      return "INFORMACIÓN";
    default:
      return categoria;
  }
}

Color colorCategoria(String categoria) {
  switch (categoria) {
    case "RESUELTO":
      return StatusColors.exitoso;
    case "DEMORADO":
      return StatusColors.demorado;
    case "EJECUTADO":
      return StatusColors.info;
    case "INFORMACION":
      return StatusColors.neutral;
    default:
      return StatusColors.critico;
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
  String? _filtroCategoria; // null=todos, o una de _categoriasFiltro
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
      builder: (_) => FormularioEntradaBitacora(
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
      final coincideCategoria =
          _filtroCategoria == null || e.categoria == _filtroCategoria;
      return coincideBusqueda &&
          coincideEstado &&
          coincideTipo &&
          coincideTecnologia &&
          coincideCategoria;
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
                  seleccionado: _filtroCategoria == null,
                  onTap: () => setState(() => _filtroCategoria = null),
                ),
                for (final categoria in _categoriasFiltro) ...[
                  const SizedBox(width: 8),
                  _ChipEstado(
                    etiqueta: etiquetaCategoria(categoria),
                    cantidad:
                        _entradas.where((e) => e.categoria == categoria).length,
                    color: colorCategoria(categoria),
                    seleccionado: _filtroCategoria == categoria,
                    onTap: () => setState(() => _filtroCategoria =
                        _filtroCategoria == categoria ? null : categoria),
                  ),
                ],
              ],
            ),
          ),
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
    final color = colorEvento(entrada);
    final estadoTexto = entrada.estado ?? (entrada.esProceso ? "ERROR" : "TABLA");
    final sistema = entrada.sistema ?? entrada.tecnologia;

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
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconoEvento(entrada), color: color, size: 18),
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
                            "$sistema · $estadoTexto",
                            style:
                                AppTextStyles.tech(color: color, fontSize: 9),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(resuelto ? "RESUELTO" : "ABIERTO",
                              style:
                                  AppTextStyles.tech(color: color, fontSize: 8)),
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
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _DatoTarjeta(
                  icono: Icons.play_arrow_outlined,
                  texto: "Inicio ${_hora(entrada.fechaHora)}"),
              if (resuelto && entrada.fechaActualizacion != null)
                _DatoTarjeta(
                    icono: Icons.flag_outlined,
                    texto: "Resuelto ${_hora(entrada.fechaActualizacion!)}"),
              _DatoTarjeta(
                  icono: Icons.timelapse,
                  texto: "Duración ${entrada.duracionFormateada}"),
              if (entrada.origen != null)
                _DatoTarjeta(
                    icono: Icons.person_outline, texto: entrada.origen!),
            ],
          ),
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
                Icon(iconoEvento(entrada), color: color, size: 15),
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

class _DatoTarjeta extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _DatoTarjeta({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 12, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(texto,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10.5)),
      ],
    );
  }
}

