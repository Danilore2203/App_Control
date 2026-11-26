import "dart:async";

import "package:flutter/material.dart";

import "../models/control.dart";
import "../services/comandos_service.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "detalle_proceso_sheet.dart";
import "fondo_app.dart";
import "titulo_seccion.dart";

/// Lo que OP_PROD ve corriendo ahora en DataStage (ps DSD.RUN en el engine) y
/// Pentaho (Carte): el contador «Corriendo» de la web (`procesos.corriendo`).
class CorriendoEnVivo {
  final List<Map<String, dynamic>> procesos;
  final List<Map<String, dynamic>> otros;
  final List<String> fuentesConError;

  /// Motores DataStage que OP mira («ds117», «ds115»…), en ese orden. Con más
  /// de uno, el filtro DataStage se parte en uno por motor (como en la web).
  final List<String> motores;

  /// Motores cuyo primer barrido sigue en curso (la 11.5 tarda unos 40 s).
  final List<String> leyendo;

  /// «10:42»: a qué hora OP miró lo que corre.
  final String? vistoALas;

  const CorriendoEnVivo({
    this.procesos = const [],
    this.otros = const [],
    this.fuentesConError = const [],
    this.motores = const [],
    this.leyendo = const [],
    this.vistoALas,
  });

  factory CorriendoEnVivo.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> lista(Object? v) =>
        ((v as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final fuentes = lista(j["fuentes"]);
    String? motorDe(Map<String, dynamic> f) {
      final n = (f["fuente"] ?? "").toString();
      if (!n.startsWith("DataStage ")) return null;
      final m = n.substring(10).trim().toLowerCase();
      return m.isEmpty ? null : m;
    }

    final generado = (j["generado_en"] ?? "").toString();
    return CorriendoEnVivo(
      procesos: lista(j["procesos"]),
      otros: lista(j["otros"]),
      fuentesConError: [
        for (final f in fuentes)
          if (f["ok"] == false && f["leyendo"] != true)
            "${f["fuente"]}: ${(f["error"] ?? "no respondió").toString()}",
      ],
      motores: [for (final f in fuentes) if (motorDe(f) != null) motorDe(f)!],
      leyendo: [for (final f in fuentes) if (f["leyendo"] == true && motorDe(f) != null) motorDe(f)!],
      vistoALas: generado.length >= 16 ? generado.substring(11, 16) : null,
    );
  }

  static const _version = {"ds117": "11.7", "ds115": "11.5", "ds150": "150"};

  /// «ds115» → «DataStage 11.5».
  static String nombreMotor(String motor) => "DataStage ${_version[motor] ?? motor}";

  /// «12:05» (hoy) o «22/10» / «22/10 07:00» (otro día) → fecha y hora.
  static DateTime? leerDesde(Object? desde, DateTime ahora) {
    final s = (desde ?? "").toString().trim();
    final hora = RegExp(r"^(\d{1,2}):(\d{2})$").firstMatch(s);
    if (hora != null) {
      return DateTime(ahora.year, ahora.month, ahora.day, int.parse(hora.group(1)!), int.parse(hora.group(2)!));
    }
    final dia = RegExp(r"^(\d{1,2})/(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?$").firstMatch(s);
    if (dia != null) {
      var f = DateTime(ahora.year, int.parse(dia.group(2)!), int.parse(dia.group(1)!),
          int.parse(dia.group(3) ?? "0"), int.parse(dia.group(4) ?? "0"));
      if (f.isAfter(ahora)) f = DateTime(f.year - 1, f.month, f.day, f.hour, f.minute);
      return f;
    }
    return null;
  }
}

/// Un proceso en ejecución, venga del catálogo (Airflow) o de OP en vivo.
class EnCurso {
  final String nombre;
  final String fuente;
  final DateTime? inicio;
  final List<String> pasos;
  final Control? control;

  /// Job que corre en el engine pero no es (directamente) un proceso del monitor.
  final bool fueraDelMonitor;

  /// Motor DataStage donde corre («ds117», «ds115»); vacío si no es DataStage
  /// en vivo.
  final String motor;

  const EnCurso({
    required this.nombre,
    required this.fuente,
    this.inicio,
    this.pasos = const [],
    this.control,
    this.fueraDelMonitor = false,
    this.motor = "",
  });

  /// «DataStage 11.5» si se sabe el motor; si no, la fuente tal cual.
  String get donde => motor.isEmpty ? fuente : CorriendoEnVivo.nombreMotor(motor);

  /// Filtro del panel: «todo», un motor («ds115») o una fuente («PENTAHO»).
  bool pasa(String origen) =>
      origen == "todo" || (origen.startsWith("ds") ? motor == origen : fuente.toUpperCase() == origen);
}

/// «Corriendo ahora»: lo que está en ejecución en este momento, con cuánto
/// lleva. Junta Airflow (del catálogo) con DataStage y Pentaho (OP los consulta
/// en vivo, cada minuto). Tocar uno abre su detalle.
class CorriendoAhora extends StatefulWidget {
  const CorriendoAhora({
    super.key,
    required this.controles,
    this.titulo = "Corriendo ahora",
    this.consultarEnVivo = true,
    this.filtroFuente,
    this.soloCore = false,
    this.cargarEnVivo,
    this.ahora,
  });

  final List<Control> controles;
  final String titulo;

  /// En la vista Tablas no tiene sentido preguntar por DataStage/Pentaho.
  final bool consultarEnVivo;

  /// Los filtros del monitor: lo que corre fuera del monitor se muestra solo
  /// si es de esa fuente (y nunca con «solo core»).
  final String? filtroFuente;
  final bool soloCore;

  /// Para las pruebas; normalmente pide `procesos.corriendo` a OP_PROD.
  final Future<CorriendoEnVivo> Function()? cargarEnVivo;
  final DateTime Function()? ahora;

  static const maximoVisibles = 5;

  /// Desde cuándo corre segun el catálogo. Airflow manda la hora en UTC y
  /// DataStage/Pentaho en hora local (sin zona en ambos casos): para Airflow se
  /// toma la lectura que no queda en el futuro.
  static DateTime? inicioDe(Control c, DateTime ahora) {
    final f = leerFechaCatalogo(c.horaLog);
    if (f == null) return null;
    if (c.fuente.toUpperCase() != "AIRFLOW") return f;
    final comoUtc = DateTime.utc(f.year, f.month, f.day, f.hour, f.minute, f.second).toLocal();
    final candidatos = [f, comoUtc].where((d) => !d.isAfter(ahora.add(const Duration(minutes: 2)))).toList()
      ..sort((a, b) => b.compareTo(a));
    return candidatos.isEmpty ? f : candidatos.first;
  }

  /// Un job del engine que no vino cruzado con el monitor: se busca su proceso
  /// por los nombres habituales (JOB_X_LOG -> X_LOG_ALL / JOB_X_LOG_ALL), solo
  /// para poder abrir su detalle.
  static Control? _procesoDelJob(String job, Map<String, Control> porNombre) {
    final j = job.toUpperCase();
    final sinJob = j.startsWith("JOB_") ? j.substring(4) : j;
    for (final n in [j, "${j}_ALL", sinJob, "${sinJob}_ALL"]) {
      final c = porNombre[n];
      if (c != null) return c;
    }
    return null;
  }

  /// Junta lo del catálogo (azul = en ejecución) con lo que OP ve en vivo:
  /// los procesos del monitor que corren y los jobs que corren fuera de él
  /// (la web también los cuenta). `controles` ya viene filtrado.
  static List<EnCurso> juntar(
    List<Control> controles,
    CorriendoEnVivo? vivo,
    DateTime ahora, {
    String? filtroFuente,
    bool soloCore = false,
  }) {
    final porNombre = {for (final c in controles) c.nombre.toUpperCase(): c};
    bool pasaFiltro(String fuente) =>
        !soloCore && (filtroFuente == null || filtroFuente.toUpperCase() == fuente.toUpperCase());
    final vistos = <String>{};
    final out = <EnCurso>[];
    for (final p in vivo?.procesos ?? const <Map<String, dynamic>>[]) {
      final nombre = (p["nombre"] ?? "").toString();
      if (nombre.isEmpty) continue;
      final c = porNombre[nombre.toUpperCase()];
      final fuente = c?.fuente ?? (p["fuente"] ?? "").toString().toUpperCase();
      if (c == null && !pasaFiltro(fuente)) continue; // fuera de los filtros puestos
      vistos.add(nombre.toUpperCase());
      out.add(EnCurso(
        nombre: nombre,
        fuente: fuente,
        inicio: CorriendoEnVivo.leerDesde(p["desde"], ahora),
        pasos: ((p["pasos"] as List?) ?? const []).map((e) => e.toString()).toList(),
        control: c,
        motor: fuente == "DATASTAGE" ? (p["target"] ?? "").toString().toLowerCase() : "",
      ));
    }
    // Lo que corre fuera del monitor (un mismo job puede tener varios PID: uno solo).
    final otros = <String, EnCurso>{};
    for (final o in vivo?.otros ?? const <Map<String, dynamic>>[]) {
      final job = (o["job"] ?? "").toString();
      final fuente = (o["fuente"] ?? "").toString().toUpperCase();
      if (job.isEmpty || !pasaFiltro(fuente)) continue;
      final c = _procesoDelJob(job, porNombre);
      if (c != null && vistos.contains(c.nombre.toUpperCase())) continue;
      final inicio = CorriendoEnVivo.leerDesde(o["desde"], ahora);
      final motor = fuente == "DATASTAGE" ? (o["target"] ?? "").toString().toLowerCase() : "";
      final clave = "$fuente|$motor|${job.toUpperCase()}";
      final previo = otros[clave];
      if (previo != null && (previo.inicio == null || (inicio != null && !inicio.isBefore(previo.inicio!)))) continue;
      otros[clave] =
          EnCurso(nombre: job, fuente: fuente, inicio: inicio, control: c, fueraDelMonitor: c == null, motor: motor);
    }
    out.addAll(otros.values);
    for (final e in otros.values) {
      if (e.control != null) vistos.add(e.control!.nombre.toUpperCase());
    }
    for (final c in controles) {
      if (c.categoria != "blue" || vistos.contains(c.nombre.toUpperCase())) continue;
      out.add(EnCurso(nombre: c.nombre, fuente: c.fuente, inicio: inicioDe(c, ahora), control: c));
    }
    out.sort((a, b) {
      // Primero los que llevan más tiempo.
      if (a.inicio == null && b.inicio == null) return a.nombre.compareTo(b.nombre);
      if (a.inicio == null) return 1;
      if (b.inicio == null) return -1;
      return a.inicio!.compareTo(b.inicio!);
    });
    return out;
  }

  @override
  State<CorriendoAhora> createState() => _CorriendoAhoraState();
}

class _CorriendoAhoraState extends State<CorriendoAhora> with WidgetsBindingObserver {
  Timer? _reloj;
  Timer? _reintento;
  int _ticks = 0;
  CorriendoEnVivo? _vivo;
  String? _errorVivo;
  bool _pidiendo = false;

  /// Filtro del panel: «todo», un motor («ds117», «ds115») o una fuente.
  String _origen = "todo";

  /// Panel plegado: queda solo la cabecera con el resumen. Se recuerda
  /// mientras la app siga abierta.
  static bool _oculto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pedir();
    // Cada 30 s avanza el tiempo; cada minuto se vuelve a preguntar a OP.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _ticks++;
      if (_ticks.isEven) _pedir();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(CorriendoAhora anterior) {
    super.didUpdateWidget(anterior);
    if (widget.consultarEnVivo && !anterior.consultarEnVivo) _pedir();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _pedir();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _reintento?.cancel();
    super.dispose();
  }

  /// [refrescar]: el botón «Actualizar» le pide a OP que no use su caché de 30 s.
  Future<void> _pedir({bool refrescar = false}) async {
    if (!widget.consultarEnVivo || _pidiendo) return;
    final estado = WidgetsBinding.instance.lifecycleState;
    if (estado != null && estado != AppLifecycleState.resumed) return;
    _pidiendo = true;
    if (refrescar && mounted) setState(() {});
    try {
      final cargar = widget.cargarEnVivo;
      final vivo = cargar != null
          ? await cargar()
          : CorriendoEnVivo.fromJson((await ComandosService().ejecutar(
              "procesos.corriendo",
              payload: refrescar ? const {"refrescar": true} : const {},
            ))
              .resultado);
      if (mounted) {
        setState(() {
          _vivo = vivo;
          _errorVivo = null;
        });
        // Primer barrido de un motor en curso: se vuelve a preguntar solo.
        _reintento?.cancel();
        if (vivo.leyendo.isNotEmpty) _reintento = Timer(const Duration(seconds: 12), _pedir);
      }
    } catch (e) {
      if (mounted) setState(() => _errorVivo = e is ComandoFallidoException ? e.mensaje : e.toString());
    } finally {
      _pidiendo = false;
      if (refrescar && mounted) setState(() {});
    }
  }

  List<String> _notas(CorriendoEnVivo? vivo) {
    final notas = <String>[];
    final error = _errorVivo;
    if (widget.consultarEnVivo && error != null) {
      notas.add(error.contains("reiniciar")
          ? "Para ver DataStage y Pentaho en vivo hay que reiniciar el OP del .150."
          : "No se pudo consultar DataStage y Pentaho: $error");
    }
    for (final f in vivo?.fuentesConError ?? const <String>[]) {
      notas.add("No respondió $f");
    }
    for (final m in vivo?.leyendo ?? const <String>[]) {
      notas.add("Leyendo por primera vez lo que corre en ${CorriendoEnVivo.nombreMotor(m)} (unos 40 s). Se actualiza solo.");
    }
    return notas;
  }

  /// Escala de la barra: lo más largo que empezó hoy (al menos una hora).
  static int _escala(List<EnCurso> items, DateTime ahora) {
    var max = 60;
    for (final i in items) {
      final ini = i.inicio;
      if (ini == null || !_esHoy(ini, ahora)) continue;
      final min = ahora.difference(ini).inMinutes;
      if (min > max) max = min;
    }
    return max;
  }

  void _verTodos(List<EnCurso> items, DateTime ahora) {
    final escala = _escala(items, ahora);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text("${widget.titulo} · ${items.length}",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final (k, i) in items.indexed) ...[
              if (k > 0) Divider(height: 1, thickness: 1, color: _colorBorde(context)),
              _Fila(item: i, ahora: ahora, escala: escala),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ahora = widget.ahora?.call() ?? DateTime.now();
    final vivo = widget.consultarEnVivo ? _vivo : null;
    final items = CorriendoAhora.juntar(
      widget.controles,
      vivo,
      ahora,
      filtroFuente: widget.filtroFuente,
      soloCore: widget.soloCore,
    );
    final notas = _notas(vivo);

    Widget pie() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final n in notas)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(n, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline, height: 1.3)),
              ),
          ],
        );

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pause_circle_outline_rounded, size: 16, color: colorScheme.outline),
                const SizedBox(width: 6),
                Flexible(
                  child: Text("Nada corriendo en este momento",
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
            pie(),
          ],
        ),
      );
    }

    // Filtros del panel: Todo / DataStage (uno por motor si OP mira más de
    // uno: 11.7 y 11.5) / Pentaho / Airflow, cada uno con cuántos corren.
    final motores = vivo?.motores ?? const <String>[];
    final hay = {for (final i in items) i.fuente.toUpperCase()};
    final opciones = <(String, String)>[
      ("todo", "Todo"),
      if (motores.length > 1)
        for (final m in motores) (m, CorriendoEnVivo.nombreMotor(m))
      else if (vivo != null || hay.contains("DATASTAGE"))
        ("DATASTAGE", "DataStage"),
      if (vivo != null || hay.contains("PENTAHO")) ("PENTAHO", "Pentaho"),
      if (hay.contains("AIRFLOW")) ("AIRFLOW", "Airflow"),
    ];
    final origen = opciones.any((o) => o.$1 == _origen) ? _origen : "todo";
    final lista = items.where((i) => i.pasa(origen)).toList();
    final escala = _escala(lista, ahora);
    final nombreOrigen = opciones.firstWhere((o) => o.$1 == origen).$2;
    final visto = vivo?.vistoALas;

    final visibles = lista.take(CorriendoAhora.maximoVisibles).toList();
    final run = _colorRun(context);
    final borde = _colorBorde(context);
    // Plegado queda el resumen de todo lo que corre; abierto, a qué hora se vio.
    final primero = items.where((i) => i.inicio != null).firstOrNull;
    final String? pista;
    if (_oculto) {
      pista = [
        "${items.length} corriendo",
        if (primero != null)
          "el que más lleva: ${primero.nombre} (${duracionCorta(ahora.difference(primero.inicio!).inSeconds)})",
        if (visto != null) "visto a las $visto",
      ].join(" · ");
    } else if (widget.consultarEnVivo && visto != null) {
      pista = "Visto a las $visto · se vuelve a preguntar cada minuto";
    } else {
      pista = null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Vidrio(
        padding: EdgeInsets.zero,
        borderColor: run.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _Pulso(color: run),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(widget.titulo,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                            ),
                            if (opciones.length <= 2) ...[
                              const SizedBox(width: 8),
                              PillEstado("${lista.length}", color: run),
                            ],
                          ],
                        ),
                        if (pista != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(pista,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline, fontSize: 11.5)),
                          ),
                      ],
                    ),
                  ),
                  if (widget.consultarEnVivo && !_oculto) ...[
                    const SizedBox(width: 8),
                    _BotonPanel(
                      key: const Key("corriendo_actualizar"),
                      icono: Icons.refresh_rounded,
                      ayuda: "Actualizar",
                      onTap: _pidiendo ? null : () => _pedir(refrescar: true),
                    ),
                  ],
                  const SizedBox(width: 6),
                  _BotonPanel(
                    key: const Key("corriendo_ocultar"),
                    icono: _oculto ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                    texto: _oculto ? "Mostrar" : "Ocultar",
                    ayuda: _oculto ? "Mostrar la lista de lo que corre" : "Ocultar la lista; queda solo el resumen",
                    onTap: () => setState(() => _oculto = !_oculto),
                  ),
                ],
              ),
            ),
            if (!_oculto) ...[
              if (opciones.length > 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: borde),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final o in opciones)
                            _Filtro(
                              key: Key("corriendo_filtro_${o.$1}"),
                              texto: o.$2,
                              cantidad: items.where((i) => i.pasa(o.$1)).length,
                              elegido: o.$1 == origen,
                              onTap: () => setState(() => _origen = o.$1),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Divider(height: 1, thickness: 1, color: borde),
              if (lista.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 4),
                  child: Row(
                    children: [
                      Icon(Icons.pause_circle_outline_rounded, size: 16, color: colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (vivo?.leyendo ?? const <String>[]).contains(origen)
                              ? "Leyendo lo que corre en $nombreOrigen… aparece solo en unos segundos."
                              : "Nada corriendo en $nombreOrigen en este momento.",
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final (k, i) in visibles.indexed) ...[
                if (k > 0) Divider(height: 1, thickness: 1, color: borde),
                _Fila(item: i, ahora: ahora, escala: escala),
              ],
              if (lista.length > visibles.length)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: TextButton(
                      key: const Key("corriendo_ver_todos"),
                      onPressed: () => _verTodos(lista, ahora),
                      style: TextButton.styleFrom(foregroundColor: run, visualDensity: VisualDensity.compact),
                      child: Text("Ver los ${lista.length}",
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              Padding(padding: const EdgeInsets.fromLTRB(14, 0, 10, 10), child: pie()),
            ],
          ],
        ),
      ),
    );
  }
}

bool _esHoy(DateTime d, DateTime ahora) => d.year == ahora.year && d.month == ahora.month && d.day == ahora.day;

bool _oscuro(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// El celeste «corriendo» de la web (--pr-run en procesos.css).
Color _colorRun(BuildContext context) => _oscuro(context) ? const Color(0xFF67E8F9) : const Color(0xFF0E7490);

/// Empezó otro día: ámbar (--pm-delay).
Color _colorViejo(BuildContext context) => _oscuro(context) ? const Color(0xFFFFC766) : const Color(0xFFC97F05);

Color _colorBorde(BuildContext context) => _oscuro(context) ? OpTokens.borderStrongDark : OpTokens.borderStrongLight;

/// Botón con borde de la cabecera del panel («Actualizar», «Ocultar»).
class _BotonPanel extends StatelessWidget {
  const _BotonPanel({super.key, required this.icono, required this.ayuda, required this.onTap, this.texto});

  final IconData icono;
  final String ayuda;
  final String? texto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withValues(alpha: onTap == null ? 0.4 : 0.9);
    return Tooltip(
      message: ayuda,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
          padding: EdgeInsets.symmetric(horizontal: texto == null ? 0 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _colorBorde(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 17, color: color),
              if (texto != null) ...[
                const SizedBox(width: 4),
                Text(texto!, style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón de filtro del panel, dentro de la cápsula: «DataStage 11.5  3».
class _Filtro extends StatelessWidget {
  const _Filtro({super.key, required this.texto, required this.cantidad, required this.elegido, required this.onTap});

  final String texto;
  final int cantidad;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final run = _colorRun(context);
    final color = elegido ? run : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: elegido,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: elegido ? run.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text.rich(
            TextSpan(
              text: texto,
              children: [
                TextSpan(text: "  $cantidad", style: TextStyle(color: color.withValues(alpha: 0.75))),
              ],
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra de cuánto lleva: degradado celeste, como en la web.
class _Barra extends StatelessWidget {
  const _Barra({required this.avance, required this.color});

  final double avance;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: FractionallySizedBox(
        widthFactor: avance,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.3), color]),
          ),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.item, required this.ahora, required this.escala});

  final EnCurso item;
  final DateTime ahora;

  /// Minutos que valen la barra entera (lo más largo que empezó hoy).
  final int escala;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final i = item;
    final inicio = i.inicio;
    final lleva = inicio == null ? null : duracionCorta(ahora.difference(inicio).inSeconds);
    // Si empezó otro día va en ámbar y con la barra llena: puede estar colgado.
    final viejo = inicio != null && !_esHoy(inicio, ahora);
    final acento = viejo ? _colorViejo(context) : _colorRun(context);
    final avance =
        inicio == null || viejo ? 1.0 : (ahora.difference(inicio).inMinutes / escala).clamp(0.03, 1.0).toDouble();
    String? desde;
    if (inicio != null && i.fuente.toUpperCase() != "AIRFLOW") {
      final hhmm = "${inicio.hour.toString().padLeft(2, "0")}:${inicio.minute.toString().padLeft(2, "0")}";
      desde = viejo ? "desde el ${inicio.day}/${inicio.month} $hhmm" : "desde las $hhmm";
    }
    final control = i.control;
    final quien = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i.nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              height: 1.2,
              fontWeight: i.fueraDelMonitor ? FontWeight.w600 : FontWeight.w700,
              color: i.fueraDelMonitor ? colorScheme.onSurface.withValues(alpha: 0.82) : colorScheme.onSurface,
            )),
        const SizedBox(height: 2),
        Text(
          [
            i.donde,
            if (desde != null) desde,
            if (i.pasos.isNotEmpty) "paso ${i.pasos.last}",
            if (i.fueraDelMonitor) "fuera del monitor",
          ].join(" · "),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline, fontSize: 11.5),
        ),
      ],
    );
    final barra = _Barra(avance: avance, color: acento);
    return InkWell(
      onTap: control == null ? null : () => mostrarDetalleProceso(context, control),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        // Como en la web: nombre, barra al medio y cuánto lleva a la derecha.
        // Si no entra (pantalla muy angosta), la barra baja a una segunda línea.
        child: LayoutBuilder(
          builder: (context, c) {
            final alMedio = c.maxWidth >= 280;
            final fila = Row(
              children: [
                Expanded(flex: 11, child: quien),
                if (alMedio) ...[
                  const SizedBox(width: 10),
                  Expanded(flex: 5, child: barra),
                ],
                const SizedBox(width: 10),
                Text(
                  lleva ?? "en curso",
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: acento,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: control == null ? Colors.transparent : colorScheme.outline),
              ],
            );
            if (alMedio) return fila;
            return Column(
              children: [
                fila,
                Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: barra),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Punto celeste que late: «esto está pasando ahora».
class _Pulso extends StatefulWidget {
  const _Pulso({required this.color});

  final Color color;

  @override
  State<_Pulso> createState() => _PulsoState();
}

class _PulsoState extends State<_Pulso> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
