import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/actualizaciones_service.dart";
import "../services/api_service.dart";
import "../theme.dart";
import "../utils/meses_es.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/formulario_entrada_bitacora.dart";
import "../widgets/pestanas.dart";
import "../widgets/titulo_seccion.dart";

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

/// Las 5 tecnologías posibles, siempre visibles como filtro (antes solo se
/// mostraban las que tenían fallas ese día, lo que hacía aparecer y
/// desaparecer el filtro entre días).
const _todasLasTecnologias = [
  "AIRFLOW",
  "DATASTAGE",
  "PENTAHO",
  "PG_PROD",
  "QA_CONTROL",
];

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
  String? _filtroEstado; // null=todos, "ABIERTO", "RESUELTO" o "DEMORADO"
  String? _filtroTecnologia;
  bool _soloCore = false;
  // Pestana como en el monitor web: GENERAL (todo), PROCESOS o TABLAS. Se
  // arranca en Procesos porque es lo que mira la guardia; las tablas (sobre
  // todo PG_PROD vacias) son muchas mas y tapaban a los procesos.
  String _vista = "PROCESOS";
  // Nombres de procesos CORE segun el estado ACTUAL de /controles (no se
  // guarda ese dato en la bitacora): cruzado por nombre contra cada entrada.
  // Aproximado a proposito -si un proceso cambio de nombre o ya no existe en
  // /controles, no va a matchear- para no tocar la tabla de bitacora.
  Set<String> _nombresCoreActuales = {};
  late final AnimationController _pulseController;
  late final SuscripcionActualizaciones _actualizaciones;

  @override
  void initState() {
    super.initState();
    _entradas = widget.entradasIniciales;
    _cargarNombresCoreActuales();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    // Esta pantalla llega con una foto fija (entradasIniciales). Se refresca
    // cuando el backend avisa que hay cambios (y al volver a primer plano),
    // en vez de preguntar cada 60 s aunque no haya nada.
    _actualizaciones = SuscripcionActualizaciones(_refrescarEntradas);
  }

  Future<void> _refrescarEntradas() async {
    if (!mounted) return;
    try {
      final nuevasEntradas =
          await _apiService.obtenerBitacoraEntradas(widget.anio, mes: widget.mes);
      if (!mounted) return;
      setState(() {
        _entradas =
            nuevasEntradas.where((e) => e.fechaHora.day == widget.dia).toList();
      });
    } catch (_) {
      // Sin red o servidor caido: se queda con lo que ya tenia.
    }
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _pulseController.dispose();
    _actualizaciones.cancelar();
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

  Future<void> _cargarNombresCoreActuales() async {
    try {
      final controles = await _apiService.obtenerControles();
      if (!mounted) return;
      setState(() {
        _nombresCoreActuales = controles
            .where((c) => (c.core ?? "").trim().toUpperCase() == "SI")
            .map((c) => c.nombre)
            .toSet();
      });
    } catch (_) {
      // Sin esto no se puede filtrar por core, pero no vale la pena romper
      // toda la pantalla de bitacora por un fallo de red puntual: el chip
      // CORE simplemente no encuentra coincidencias hasta el proximo intento.
    }
  }

  /// Una incoherencia (proceso -> tabla) tiene nombre compuesto: para saber
  /// si es de un proceso CORE hay que comparar solo la parte del proceso.
  String _nombreProcesoDe(BitacoraError e) {
    final indice = e.nombre.indexOf(" -> ");
    return indice == -1 ? e.nombre : e.nombre.substring(0, indice);
  }

  /// Bucket exclusivo para los 4 filtros pedidos: un demorado no cuenta como
  /// "abierto" aparte (tiene su propio filtro), igual que en Controles
  /// "Con error" y "Demorados" son categorías separadas.
  String _bucketEstado(BitacoraError e) {
    if (e.resuelto) return "RESUELTO";
    if ((e.estado ?? "").toUpperCase() == "DEMORADO") return "DEMORADO";
    return "ABIERTO";
  }

  bool _esIncoherencia(BitacoraError e) =>
      (e.estado ?? "").toUpperCase() == "INCOHERENCIA";

  bool _enVista(BitacoraError e) => switch (_vista) {
        "PROCESOS" => e.esProceso,
        "TABLAS" => !e.esProceso,
        _ => true,
      };

  /// Tecnologias que tienen sentido en la pestana actual (procesos o
  /// tablas); en General, todas.
  List<String> get _tecnologiasDeLaVista => switch (_vista) {
        "PROCESOS" => tecnologiasProceso,
        "TABLAS" => tecnologiasTabla,
        _ => _todasLasTecnologias,
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final busquedaLimpia = _busqueda.trim().toLowerCase();
    // Base para los indicadores, los chips y la lista: pestana + busqueda +
    // tecnologia + core ya aplicados. El filtro de ESTADO (chips) se aplica
    // despues, aparte, porque son las opciones entre las que el usuario
    // esta eligiendo: no tendria sentido que se filtraran a si mismas.
    final entradasVisibles = _entradas.where((e) {
      final coincideBusqueda = busquedaLimpia.isEmpty ||
          e.nombre.toLowerCase().contains(busquedaLimpia) ||
          e.tecnologia.toLowerCase().contains(busquedaLimpia) ||
          e.descripcion.toLowerCase().contains(busquedaLimpia);
      final coincideTecnologia =
          _filtroTecnologia == null || e.tecnologia == _filtroTecnologia;
      final coincideCore =
          !_soloCore || _nombresCoreActuales.contains(_nombreProcesoDe(e));
      return _enVista(e) && coincideBusqueda && coincideTecnologia && coincideCore;
    }).toList();
    final abiertos =
        entradasVisibles.where((e) => _bucketEstado(e) == "ABIERTO").length;
    final resueltos =
        entradasVisibles.where((e) => _bucketEstado(e) == "RESUELTO").length;
    final demorados =
        entradasVisibles.where((e) => _bucketEstado(e) == "DEMORADO").length;
    final incoherencias = entradasVisibles.where(_esIncoherencia).length;
    final total = entradasVisibles.length;
    final pctCritico = total == 0 ? 0 : ((abiertos + demorados) * 100 / total).round();
    final entradasFiltradas = entradasVisibles
        .where((e) => _filtroEstado == null || _bucketEstado(e) == _filtroEstado)
        .toList();
    final totalProcesos = _entradas.where((e) => e.esProceso).length;
    final totalTablas = _entradas.length - totalProcesos;

    void elegirEstado(String? estado) =>
        setState(() => _filtroEstado = _filtroEstado == estado ? null : estado);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Eyebrow("Registro de incidentes"),
            Text("${widget.dia} de ${nombresMesEs[widget.mes - 1]}"),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        icon: const Icon(Icons.add),
        label: const Text("Registrar"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          // Pestanas General / Procesos / Tablas, como el monitor web.
          Pestanas(
            seleccionada: _vista,
            opciones: [
              ("GENERAL", "General", _entradas.length),
              ("PROCESOS", "Procesos", totalProcesos),
              ("TABLAS", "Tablas", totalTablas),
            ],
            onCambiar: (vista) => setState(() {
              _vista = vista;
              _filtroTecnologia = null;
              _filtroEstado = null;
            }),
          ),
          const SizedBox(height: 14),
          // Indicadores del dia (.bt-kpi-tile): tocar uno filtra la lista.
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.35,
            children: [
              IndicadorTile(
                etiqueta: "Total",
                valor: "$total",
                icono: Icons.list_alt_outlined,
                onTap: () => elegirEstado(null),
              ),
              IndicadorTile(
                etiqueta: "Error",
                valor: "$abiertos",
                color: StatusColors.critico,
                icono: Icons.error_outline,
                onTap: () => elegirEstado("ABIERTO"),
              ),
              IndicadorTile(
                etiqueta: "Resueltos",
                valor: "$resueltos",
                color: StatusColors.exitoso,
                icono: Icons.check_circle_outline,
                onTap: () => elegirEstado("RESUELTO"),
              ),
              IndicadorTile(
                etiqueta: "Demorados",
                valor: "$demorados",
                color: StatusColors.demorado,
                icono: Icons.schedule,
                onTap: () => elegirEstado("DEMORADO"),
              ),
              IndicadorTile(
                etiqueta: "Incoherencias",
                valor: "$incoherencias",
                color: StatusColors.info,
                icono: Icons.compare_arrows,
              ),
              IndicadorTile(
                etiqueta: "Crítico",
                valor: "$pctCritico%",
                color: pctCritico >= 50
                    ? StatusColors.critico
                    : pctCritico > 0
                        ? StatusColors.demorado
                        : StatusColors.exitoso,
                icono: Icons.speed_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _busquedaController,
            onChanged: (valor) => setState(() => _busqueda = valor),
            decoration: InputDecoration(
              hintText: "Buscar por nombre, tecnología o descripción...",
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
                  etiqueta: "Todos",
                  cantidad: total,
                  color: colorScheme.primary,
                  seleccionado: _filtroEstado == null,
                  onTap: () => setState(() => _filtroEstado = null),
                ),
                const SizedBox(width: 8),
                _ChipEstado(
                  etiqueta: "Error",
                  cantidad: abiertos,
                  color: StatusColors.critico,
                  seleccionado: _filtroEstado == "ABIERTO",
                  onTap: () => elegirEstado("ABIERTO"),
                ),
                const SizedBox(width: 8),
                _ChipEstado(
                  etiqueta: "Demorados",
                  cantidad: demorados,
                  color: StatusColors.demorado,
                  seleccionado: _filtroEstado == "DEMORADO",
                  onTap: () => elegirEstado("DEMORADO"),
                ),
                const SizedBox(width: 8),
                _ChipEstado(
                  etiqueta: "Resueltos",
                  cantidad: resueltos,
                  color: StatusColors.exitoso,
                  seleccionado: _filtroEstado == "RESUELTO",
                  onTap: () => elegirEstado("RESUELTO"),
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
                if (_vista != "TABLAS") ...[
                  _ChipCore(
                    seleccionado: _soloCore,
                    onTap: () => setState(() => _soloCore = !_soloCore),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final tecnologia in _tecnologiasDeLaVista) ...[
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
          const SizedBox(height: 16),
          TituloSeccion(
            "Bitácora del ${widget.anio}-${widget.mes.toString().padLeft(2, '0')}-${widget.dia.toString().padLeft(2, '0')}",
            accion: Text(
              "${entradasFiltradas.length} de $total",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          ),
          const SizedBox(height: 10),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colorTexto = seleccionado ? Colors.white : colorScheme.onSurface;
    return Material(
      color: seleccionado ? color : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: seleccionado ? Colors.transparent : colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!seleccionado) ...[
                Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                const SizedBox(width: 6),
              ],
              Text(
                etiqueta,
                style: theme.textTheme.labelMedium?.copyWith(color: colorTexto, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 5),
              Text(
                "$cantidad",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorTexto.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filtra solo entradas de procesos CORE, cruzando por nombre contra el
/// estado ACTUAL de /controles (ver _nombresCoreActuales): la bitacora no
/// guarda ese dato. Entradas de TABLA, o de un proceso que ya no figura en
/// /controles (renombrado, eliminado), quedan afuera mientras este chip este
/// activo -no se muestran como "no core", simplemente no matchean.
class _ChipCore extends StatelessWidget {
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipCore({required this.seleccionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _ChipIcono(
      icono: Icons.bolt_rounded,
      texto: "Core",
      color: StatusColors.critico,
      seleccionado: seleccionado,
      onTap: onTap,
    );
  }
}

/// Chip con icono y tono propio: lleno cuando esta seleccionado, al 12 %
/// con borde cuando no.
class _ChipIcono extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipIcono({
    required this.icono,
    required this.texto,
    required this.color,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorTexto = seleccionado ? Colors.white : color;
    return Material(
      color: seleccionado ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: seleccionado ? 0 : 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 14, color: colorTexto),
              const SizedBox(width: 6),
              Text(
                texto,
                style: theme.textTheme.labelMedium?.copyWith(color: colorTexto, fontWeight: FontWeight.w700),
              ),
            ],
          ),
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
    return _ChipIcono(
      icono: iconoTecnologia(tecnologia),
      texto: tecnologia,
      color: colorTecnologia(tecnologia),
      seleccionado: seleccionado,
      onTap: onTap,
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

    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: resuelto ? colorScheme.outlineVariant : color.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CajaIcono(iconoEvento(entrada), color: color, tamano: 36, tamanoIcono: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Eyebrow("$sistema · $estadoTexto", color: color)),
                        PillEstado(resuelto ? "Resuelto" : "Abierto", color: color),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entrada.nombre,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
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
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 16,
                  margin: const EdgeInsets.only(top: 1, right: 9),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
                Expanded(
                  child: Text(
                    entrada.descripcion,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface, height: 1.4),
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

