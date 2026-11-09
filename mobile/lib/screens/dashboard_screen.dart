import "dart:async";

import "package:flutter/material.dart";

import "../models/control.dart";
import "../models/usuario.dart";
import "../services/actualizaciones_service.dart";
import "../services/api_service.dart";
import "../services/infra_service.dart";
import "../theme.dart";
import "bitacora_screen.dart";
import "configuracion_guardia_screen.dart";
import "infraestructura_screen.dart";
import "../widgets/alerta_banner.dart";
import "../widgets/app_drawer.dart";
import "../widgets/barra_navegacion.dart";
import "../widgets/detalle_proceso_sheet.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/monitoreo_por_fuente.dart";
import "../widgets/pestanas.dart";
import "../widgets/salud_sistema.dart";
import "../widgets/tarjeta_proceso.dart";
import "../widgets/titulo_seccion.dart";
import "alertas_screen.dart";

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _tabActual = 0;
  final _apiService = ApiService();
  final _infraService = InfraService();
  late Future<_Catalogo> _controlesFuture;
  // General / Procesos / Tablas, como el monitor web. Arranca en Procesos:
  // es lo que la app mostro siempre y lo que mas se mira.
  String _vista = "PROCESOS";
  String? _filtroColor;
  String? _filtroFuente;
  bool _filtroSoloCore = false;
  Usuario? _usuario;
  final _busquedaController = TextEditingController();
  final _busquedaFocus = FocusNode();
  String _busqueda = "";
  Timer? _vigiaBloqueosProd;
  int _bloqueadasProd = 0;
  bool _bannerBloqueosDescartado = false;
  int _fallosConsecutivosBloqueos = 0;

  late final SuscripcionActualizaciones _actualizaciones;

  @override
  void initState() {
    super.initState();
    _controlesFuture = _cargarCatalogo();
    _iniciarVigiaBloqueosProd();
    // Refresca cuando el backend avisa que hay catalogos nuevos (y al volver
    // a primer plano), en vez de preguntar cada 60 s aunque no haya nada.
    // No toca los filtros que el usuario tenga puestos (a diferencia de
    // _recargarControles, que los resetea porque ese es un refresh explicito
    // del usuario).
    _actualizaciones = SuscripcionActualizaciones(() {
      if (!mounted) return;
      setState(() => _controlesFuture = _cargarCatalogo());
    });
    _apiService.obtenerPerfil().then((usuario) {
      if (mounted) setState(() => _usuario = usuario);
    }).catchError((_) {
      // El menu simplemente no muestra la seccion de admin si esto falla.
    });
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _busquedaFocus.dispose();
    _vigiaBloqueosProd?.cancel();
    _actualizaciones.cancelar();
    super.dispose();
  }

  /// Corre en toda la app (no solo en Infraestructura): cada 60s consulta si
  /// hay sesiones bloqueadas en PostgreSQL PROD, igual que hace el monitor
  /// web. Si no hay infra_token (login con Google) queda callado.
  void _iniciarVigiaBloqueosProd() {
    Future<void> consultar() async {
      try {
        final resultado = await _infraService.postgresProdAlertPoll();
        if (!mounted) return;
        setState(() {
          if (resultado.bloqueadas > 0 &&
              resultado.bloqueadas != _bloqueadasProd) {
            _bannerBloqueosDescartado = false;
          }
          _bloqueadasProd = resultado.bloqueadas;
        });
        _fallosConsecutivosBloqueos = 0;
      } catch (_) {
        // Sin infra_token o monitor no disponible: no interrumpe el resto de la app.
        _fallosConsecutivosBloqueos++;
      }
      if (!mounted) return;
      // Si viene fallando seguido, espacia los reintentos (hasta 10 min) en
      // vez de insistir cada 60s sin necesidad - ahorra batería/datos cuando
      // no hay infra_token o el monitor esta caido por un rato largo.
      final segundos = _fallosConsecutivosBloqueos == 0
          ? 60
          : (60 * (1 << _fallosConsecutivosBloqueos.clamp(0, 4))).clamp(60, 600);
      _vigiaBloqueosProd = Timer(Duration(seconds: segundos), consultar);
    }

    consultar();
  }

  Color _colorEstado(String categoria) {
    switch (categoria) {
      case "red":
        return StatusColors.critico;
      case "orange":
        return StatusColors.advertencia;
      case "green":
        return StatusColors.exitoso;
      case "blue":
        return StatusColors.info;
      case "tiempo":
        return StatusColors.neutral;
      default:
        return StatusColors.neutral;
    }
  }

  /// Mismas etiquetas que los contadores del monitor web de procesos.
  String _etiquetaColor(String categoria) {
    switch (categoria) {
      case "red":
        return "Error";
      case "orange":
        return "Demorado";
      case "green":
        return "OK";
      case "blue":
        return "Actualizando";
      case "tiempo":
        return "En proceso";
      default:
        return "Sin ejecución";
    }
  }

  String _bucketDe(Control c) => c.categoria;

  /// Procesos y tablas en paralelo (dos endpoints), para que el selector
  /// General / Procesos / Tablas cambie de vista sin volver a pedir nada.
  /// Fuentes de tablas que muestra el monitor: las del "Control de tablas"
  /// (QA_CONTROL, 290 tablas con OK/Error como en la web). El catalogo trae
  /// ademas ~1.500 tablas de PG_PROD (medallion) que la web no lista en ese
  /// monitor; se dejan afuera para que la app cuente lo mismo que la web.
  static const _fuentesTablasMonitor = {"QA_CONTROL"};

  Future<_Catalogo> _cargarCatalogo() async {
    final resultados = await Future.wait([
      _apiService.obtenerControles(),
      // Si fallan solo las tablas (backend viejo sin /tablas, timeout), los
      // procesos se muestran igual y la pestana Tablas queda en 0.
      _apiService.obtenerTablas().catchError((_) => <Control>[]),
    ]);
    return _Catalogo(
      procesos: resultados[0],
      tablas: resultados[1].where((t) => _fuentesTablasMonitor.contains(t.fuente)).toList(),
    );
  }

  List<Control> _segunVista(_Catalogo catalogo) {
    switch (_vista) {
      case "PROCESOS":
        return catalogo.procesos;
      case "TABLAS":
        return catalogo.tablas;
      default:
        return [...catalogo.procesos, ...catalogo.tablas];
    }
  }

  String get _tituloLista {
    switch (_vista) {
      case "PROCESOS":
        return "Procesos";
      case "TABLAS":
        return "Tablas";
      default:
        return "Procesos y tablas";
    }
  }

  Future<void> _recargarControles() async {
    final future = _cargarCatalogo();
    setState(() {
      _controlesFuture = future;
      _filtroColor = null;
      _filtroFuente = null;
      _filtroSoloCore = false;
    });
    await future;
  }

  Widget _buildFiltros(List<Control> controles) {
    final conteos = <String, int>{};
    for (final control in controles) {
      final bucket = _bucketDe(control);
      conteos[bucket] = (conteos[bucket] ?? 0) + 1;
    }
    // Mismo orden que los contadores del monitor web (OK, Error, Demorado,
    // Actualizando, En proceso); "Sin ejecucion" solo si hay alguno, para no
    // mostrar una categoria que en DataStage/Pentaho no existe.
    final ordenColores = [
      "green",
      "red",
      "orange",
      "blue",
      "tiempo",
      if ((conteos["gray"] ?? 0) > 0) "gray",
    ];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FiltroPill(
            texto: "Todos (${controles.length})",
            seleccionado: _filtroColor == null &&
                _filtroFuente == null &&
                !_filtroSoloCore,
            onTap: () => setState(() {
              _filtroColor = null;
              _filtroFuente = null;
              _filtroSoloCore = false;
            }),
          ),
          const SizedBox(width: 8),
          for (final color in ordenColores) ...[
            _FiltroPill(
              texto: "${_etiquetaColor(color)} (${conteos[color] ?? 0})",
              punto: _colorEstado(color),
              seleccionado: _filtroColor == color,
              onTap: () => setState(
                  () => _filtroColor = _filtroColor == color ? null : color),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildListaControlesSliver(
      List<Control> controles, ColorScheme colorScheme) {
    if (controles.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: EstadoVacio(
            icono: Icons.filter_alt_off_outlined,
            mensaje: "Nada que mostrar con estos filtros",
            detalle: "Probá con otro estado, fuente o búsqueda.",
            colorIcono: colorScheme.outline,
          ),
        ),
      );
    }

    return SliverList.separated(
      itemCount: controles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final esUltimo = index == controles.length - 1;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, esUltimo ? 12 : 0),
          child: TarjetaProceso(
            control: controles[index],
            onTap: () => mostrarDetalleProceso(context, controles[index]),
          ),
        );
      },
    );
  }

  Widget _buildBusqueda(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _busquedaController,
        focusNode: _busquedaFocus,
        onChanged: (valor) =>
            setState(() => _busqueda = valor.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: _vista == "TABLAS"
              ? "Buscar tablas..."
              : "Buscar procesos, ETLs o tablas...",
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
    );
  }

  Widget _buildEncabezadoLista(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TituloSeccion(_tituloLista),
    );
  }

  Widget _buildPestanas(_Catalogo catalogo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Pestanas(
        seleccionada: _vista,
        opciones: [
          ("GENERAL", "General",
              catalogo.procesos.length + catalogo.tablas.length),
          ("PROCESOS", "Procesos", catalogo.procesos.length),
          ("TABLAS", "Tablas", catalogo.tablas.length),
        ],
        onCambiar: (vista) => setState(() {
          _vista = vista;
          // Los filtros de fuente/core/estado eran de la vista anterior.
          _filtroColor = null;
          _filtroFuente = null;
          _filtroSoloCore = false;
        }),
      ),
    );
  }

  Widget _buildControles() {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<_Catalogo>(
      future: _controlesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EstadoVacio(
            icono: Icons.cloud_off_rounded,
            mensaje: "No se pudieron cargar los controles",
            detalle: "Revisá la conexión e intentá de nuevo.",
            colorIcono: colorScheme.error,
            onReintentar: _recargarControles,
          );
        }

        final catalogo = snapshot.data ?? const _Catalogo();
        if (catalogo.procesos.isEmpty && catalogo.tablas.isEmpty) {
          return EstadoVacio(
            icono: Icons.checklist_rtl,
            mensaje: "Todavía no hay controles registrados",
            colorIcono: colorScheme.onSurfaceVariant,
          );
        }
        final todos = _segunVista(catalogo);

        final segunFuente = _filtroFuente == null
            ? todos
            : todos.where((c) => c.fuente == _filtroFuente).toList();
        final segunCore =
            _filtroSoloCore ? segunFuente.where(esCore).toList() : segunFuente;

        var controles = _filtroColor == null
            ? segunCore
            : segunCore.where((c) => _bucketDe(c) == _filtroColor).toList();
        if (_busqueda.isNotEmpty) {
          controles = controles
              .where((c) =>
                  c.nombre.toLowerCase().contains(_busqueda) ||
                  c.fuente.toLowerCase().contains(_busqueda))
              .toList();
        }

        // Como en el monitor web: "error" es rojo de verdad; un demorado va
        // aparte (el backend lo pinta rojo para la alarma, pero no se cuenta
        // como error en el resumen).
        final criticos = todos.where((c) => c.color == "red" && !c.esDemorado).toList();
        final fuentesCriticas = criticos.map((c) => c.fuente).toSet().toList();

        return Column(
          children: [
            AlertaBanner(
              cantidadCriticos: criticos.length,
              cantidadDemorados: todos.where((c) => c.esDemorado).length,
              fuentesAfectadas: fuentesCriticas,
              onTap: () => setState(() => _filtroColor = "red"),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _recargarControles,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _buildPestanas(catalogo),
                          // La salud responde a la fuente/core elegidos, para
                          // poder comparar AIRFLOW o DATASTAGE con su monitor.
                          SaludSistema(controles: segunCore),
                          MonitoreoPorFuente(
                            controles: todos,
                            fuenteSeleccionada: _filtroFuente,
                            onSeleccionarFuente: (fuente) => setState(() =>
                                _filtroFuente =
                                    _filtroFuente == fuente ? null : fuente),
                            coreSeleccionado: _filtroSoloCore,
                            onSeleccionarCore: () => setState(
                                () => _filtroSoloCore = !_filtroSoloCore),
                          ),
                          const SizedBox(height: 8),
                          _buildFiltros(segunCore),
                          const SizedBox(height: 14),
                          _buildBusqueda(colorScheme),
                          const SizedBox(height: 16),
                          _buildEncabezadoLista(colorScheme),
                        ],
                      ),
                    ),
                    _buildListaControlesSliver(controles, colorScheme),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final vistas = [
      _buildControles(),
      const AlertasScreen(),
      const GuardiaContenido(),
      const BitacoraContenido(),
    ];
    final inicial = (_usuario?.nombre ?? _usuario?.username ?? "?").trim();

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        titleSpacing: 12,
        leading: Center(
          child: Material(
            color: colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.menu_rounded, color: colorScheme.onSurface, size: 22),
              ),
            ),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (_tabActual) {
                0 => "Monitor de procesos",
                1 => "Alertas",
                2 => "Guardia",
                _ => "Bitácora",
              },
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
            ),
            if (_tabActual == 0) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PuntoEnVivo(color: StatusColors.exitoso),
                  const SizedBox(width: 5),
                  Text(
                    "SISTEMA EN VIVO",
                    style: AppTextStyles.tech(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (_tabActual == 0)
            IconButton(
              onPressed: () => _busquedaFocus.requestFocus(),
              icon: const Icon(Icons.search_rounded),
              tooltip: "Buscar",
            ),
          Padding(
            padding: const EdgeInsets.only(right: 14, left: 2),
            child: GestureDetector(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withValues(alpha: 0.16),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Text(
                  inicial.isEmpty ? "?" : inicial[0].toUpperCase(),
                  style: TextStyle(
                      color: acentoTinta(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: AppDrawer(
        usuario: _usuario,
        tabActual: _tabActual,
        onSeleccionarTab: (indice) => setState(() => _tabActual = indice),
      ),
      body: Column(
        children: [
          if (_bloqueadasProd > 0 && !_bannerBloqueosDescartado)
            _BannerBloqueosProd(
              cantidad: _bloqueadasProd,
              onVerDetalle: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InfraestructuraScreen()),
              ),
              onCerrar: () => setState(() => _bannerBloqueosDescartado = true),
            ),
          Expanded(child: vistas[_tabActual]),
        ],
      ),
      bottomNavigationBar: BarraNavegacion(
        indice: _tabActual,
        onSeleccionar: (index) => setState(() => _tabActual = index),
        destinos: const [
          DestinoNavegacion(
              icono: Icons.grid_view_outlined, iconoActivo: Icons.grid_view_rounded, etiqueta: "Controles"),
          DestinoNavegacion(
              icono: Icons.notifications_outlined, iconoActivo: Icons.notifications_rounded, etiqueta: "Alertas"),
          DestinoNavegacion(icono: Icons.shield_outlined, iconoActivo: Icons.shield_rounded, etiqueta: "Guardia"),
          DestinoNavegacion(
              icono: Icons.menu_book_outlined, iconoActivo: Icons.menu_book_rounded, etiqueta: "Bitácora"),
        ],
      ),
    );
  }
}

/// Procesos y tablas tal como los devuelve la API, ya separados; la vista
/// elegida decide cuales se muestran.
class _Catalogo {
  final List<Control> procesos;
  final List<Control> tablas;

  const _Catalogo({this.procesos = const [], this.tablas = const []});
}

/// Banner persistente en toda la app (no solo en Infraestructura) cuando hay
/// sesiones bloqueadas en PostgreSQL PROD: es la alerta mas urgente del
/// modulo de infraestructura, asi que se ve sin importar en que pestana este.
class _BannerBloqueosProd extends StatelessWidget {
  final int cantidad;
  final VoidCallback onVerDetalle;
  final VoidCallback onCerrar;

  const _BannerBloqueosProd({
    required this.cantidad,
    required this.onVerDetalle,
    required this.onCerrar,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onVerDetalle,
        child: MensajeInline(
          "PostgreSQL PROD: $cantidad sesión${cantidad == 1 ? '' : 'es'} bloqueada${cantidad == 1 ? '' : 's'}. Tocá para revisar.",
          icono: Icons.lock_clock_rounded,
          onCerrar: onCerrar,
        ),
      ),
    );
  }
}

/// Pastilla de filtro tipo capsula: punto de color + etiqueta, sin el
/// checkmark de ChoiceChip (quedaba superpuesto feo con el punto de color).
class _FiltroPill extends StatelessWidget {
  final String texto;
  final Color? punto;
  final bool seleccionado;
  final VoidCallback onTap;

  const _FiltroPill({
    required this.texto,
    this.punto,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final esTodos = punto == null;
    final colorAcento = punto ?? colorScheme.primary;

    final Color fondo;
    final Color colorTexto;
    final Border? borde;

    if (esTodos && seleccionado) {
      fondo = colorScheme.primary;
      colorTexto = colorScheme.onPrimary;
      borde = null;
    } else {
      fondo = colorScheme.surfaceContainerHigh.withValues(alpha: 0.6);
      colorTexto = colorScheme.onSurface;
      borde = Border.all(
        color: seleccionado
            ? colorAcento
            : colorScheme.outlineVariant.withValues(alpha: 0.4),
        width: seleccionado ? 1.4 : 1,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(999),
            border: borde,
            boxShadow: seleccionado && !esTodos
                ? [
                    BoxShadow(
                        color: colorAcento.withValues(alpha: 0.25),
                        blurRadius: 8)
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (punto != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: punto),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                texto,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colorTexto),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Punto verde con anillo de pulso (equivalente al "animate-ping" del
/// diseno web) para la etiqueta "SISTEMA EN VIVO" del encabezado.
class _PuntoEnVivo extends StatefulWidget {
  final Color color;

  const _PuntoEnVivo({required this.color});

  @override
  State<_PuntoEnVivo> createState() => _PuntoEnVivoState();
}

class _PuntoEnVivoState extends State<_PuntoEnVivo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      height: 8,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t).clamp(0.0, 1.0) * 0.6,
                child: Transform.scale(
                  scale: 1 + t * 1.6,
                  child: Container(
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: widget.color),
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}
