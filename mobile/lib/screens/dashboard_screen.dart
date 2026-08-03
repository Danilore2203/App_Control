import "dart:async";

import "package:flutter/material.dart";

import "../models/control.dart";
import "../models/usuario.dart";
import "../services/api_service.dart";
import "../services/infra_service.dart";
import "../theme.dart";
import "bitacora_screen.dart";
import "configuracion_guardia_screen.dart";
import "infraestructura_screen.dart";
import "../widgets/alerta_banner.dart";
import "../widgets/app_drawer.dart";
import "../widgets/detalle_proceso_sheet.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/monitoreo_por_fuente.dart";
import "../widgets/salud_sistema.dart";
import "../widgets/tarjeta_proceso.dart";
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
  late Future<List<Control>> _controlesFuture;
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

  Timer? _autoRefrescoControles;

  @override
  void initState() {
    super.initState();
    _controlesFuture = _apiService.obtenerControles();
    _iniciarVigiaBloqueosProd();
    _iniciarAutoRefrescoControles();
    _apiService.obtenerPerfil().then((usuario) {
      if (mounted) setState(() => _usuario = usuario);
    }).catchError((_) {
      // El menu simplemente no muestra la seccion de admin si esto falla.
    });
  }

  /// Sin esto, la lista de controles quedaba con la foto de cuando se abrio
  /// la pantalla hasta que el usuario la cerraba y volvia a entrar (o hacia
  /// pull-to-refresh a mano): un proceso podia cambiar de estado en el
  /// origen y la app se lo perdia hasta el proximo reingreso. Refresca sola
  /// cada 60s (mismo ritmo que el poller del backend), sin tocar los
  /// filtros que el usuario tenga puestos (a diferencia de
  /// _recargarControles, que los resetea porque ese es un refresh explicito
  /// del usuario).
  void _iniciarAutoRefrescoControles() {
    _autoRefrescoControles = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      setState(() => _controlesFuture = _apiService.obtenerControles());
    });
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _busquedaFocus.dispose();
    _vigiaBloqueosProd?.cancel();
    _autoRefrescoControles?.cancel();
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

  Color _colorEstado(String color) {
    switch (color) {
      case "red":
        return StatusColors.critico;
      case "orange":
        return StatusColors.advertencia;
      case "green":
        return StatusColors.exitoso;
      case "blue":
        return StatusColors.info;
      default:
        return Colors.grey;
    }
  }

  String _etiquetaColor(String color) {
    switch (color) {
      case "red":
        return "Con error";
      case "orange":
        return "Demorados";
      case "green":
        return "OK";
      case "blue":
        return "En ejecución";
      default:
        return "Otros";
    }
  }

  String _bucketDe(Control c) => c.esDemorado ? "orange" : c.color;

  Future<void> _recargarControles() async {
    final future = _apiService.obtenerControles();
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
    // Orden fijo: primero lo urgente (rojo/naranja), despues el resto.
    // Siempre se muestran las 5 (aunque una este en 0), para que "Demorados"
    // no aparezca y desaparezca segun si hay algun proceso demorado ahora.
    const ordenColores = ["red", "orange", "blue", "green", "gray"];
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
          padding: const EdgeInsets.all(32),
          child: EstadoVacio(
            icono: Icons.filter_alt_off_outlined,
            mensaje: "No hay controles con ese estado",
            colorIcono: colorScheme.onSurfaceVariant,
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
          hintText: "Buscar procesos o ETLs...",
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
      child: Text(
        "RECIENTES (HOY)",
        style: AppTextStyles.tech(
            color: colorScheme.onSurfaceVariant, fontSize: 10),
      ),
    );
  }

  Widget _buildControles() {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<Control>>(
      future: _controlesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EstadoVacio(
            icono: Icons.error_outline,
            mensaje: "No se pudieron cargar los controles.",
            colorIcono: colorScheme.error,
            onReintentar: _recargarControles,
          );
        }

        final todos = snapshot.data ?? [];
        if (todos.isEmpty) {
          return EstadoVacio(
            icono: Icons.checklist_rtl,
            mensaje: "Todavía no hay controles registrados",
            colorIcono: colorScheme.onSurfaceVariant,
          );
        }

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

        final criticos = todos.where((c) => c.color == "red").toList();
        final fuentesCriticas = criticos.map((c) => c.fuente).toSet().toList();

        return Column(
          children: [
            AlertaBanner(
              cantidadCriticos: criticos.length,
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
                          SaludSistema(controles: todos),
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
        leading: IconButton(
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: Container(
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.menu, color: colorScheme.onPrimary, size: 20),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (_tabActual) {
                0 => "MONITOR DE PROCESOS",
                1 => "CENTRO DE ALERTAS",
                2 => "CONFIGURACIÓN DE GUARDIA",
                _ => "BITÁCORA",
              },
              style: AppTextStyles.tech(
                color: colorScheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
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
              icon: const Icon(Icons.search),
              tooltip: "Buscar",
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.surfaceContainerHighest,
              child: Text(
                inicial.isEmpty ? "?" : inicial[0].toUpperCase(),
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabActual,
        onDestinationSelected: (index) => setState(() => _tabActual = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.checklist), label: "Controles"),
          NavigationDestination(
              icon: Icon(Icons.notifications_active), label: "Alertas"),
          NavigationDestination(
              icon: Icon(Icons.shield_outlined), label: "Guardia"),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined), label: "Bitácora"),
        ],
      ),
    );
  }
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
    return Material(
      color: StatusColors.critico,
      child: InkWell(
        onTap: onVerDetalle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.lock_clock, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "PostgreSQL PROD: $cantidad sesión${cantidad == 1 ? '' : 'es'} bloqueada${cantidad == 1 ? '' : 's'}. Revisión urgente.",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: onCerrar,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
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
