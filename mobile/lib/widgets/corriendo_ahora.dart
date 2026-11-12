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

  const CorriendoEnVivo({this.procesos = const [], this.otros = const [], this.fuentesConError = const []});

  factory CorriendoEnVivo.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> lista(Object? v) =>
        ((v as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    return CorriendoEnVivo(
      procesos: lista(j["procesos"]),
      otros: lista(j["otros"]),
      fuentesConError: [
        for (final f in lista(j["fuentes"]))
          if (f["ok"] == false) "${f["fuente"]}: ${(f["error"] ?? "no respondió").toString()}",
      ],
    );
  }

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

  const EnCurso({
    required this.nombre,
    required this.fuente,
    this.inicio,
    this.pasos = const [],
    this.control,
    this.fueraDelMonitor = false,
  });
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
      final clave = "$fuente|${job.toUpperCase()}";
      final previo = otros[clave];
      if (previo != null && (previo.inicio == null || (inicio != null && !inicio.isBefore(previo.inicio!)))) continue;
      otros[clave] = EnCurso(nombre: job, fuente: fuente, inicio: inicio, control: c, fueraDelMonitor: c == null);
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
  int _ticks = 0;
  CorriendoEnVivo? _vivo;
  String? _errorVivo;
  bool _pidiendo = false;

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
    super.dispose();
  }

  Future<void> _pedir() async {
    if (!widget.consultarEnVivo || _pidiendo) return;
    final estado = WidgetsBinding.instance.lifecycleState;
    if (estado != null && estado != AppLifecycleState.resumed) return;
    _pidiendo = true;
    try {
      final cargar = widget.cargarEnVivo;
      final vivo = cargar != null
          ? await cargar()
          : CorriendoEnVivo.fromJson((await ComandosService().ejecutar("procesos.corriendo")).resultado);
      if (mounted) {
        setState(() {
          _vivo = vivo;
          _errorVivo = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorVivo = e is ComandoFallidoException ? e.mensaje : e.toString());
    } finally {
      _pidiendo = false;
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
    return notas;
  }

  void _verTodos(List<EnCurso> items, DateTime ahora) {
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
            for (final i in items) _Fila(item: i, ahora: ahora),
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
                Text("Nada corriendo en este momento",
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ),
            pie(),
          ],
        ),
      );
    }

    final visibles = items.take(CorriendoAhora.maximoVisibles).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Vidrio(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        borderColor: StatusColors.info.withValues(alpha: 0.45),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Pulso(),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(widget.titulo,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                PillEstado("${items.length}", color: StatusColors.info),
                const Spacer(),
                if (items.length > visibles.length)
                  TextButton(
                    key: const Key("corriendo_ver_todos"),
                    onPressed: () => _verTodos(items, ahora),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text("Ver los ${items.length}"),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final i in visibles) _Fila(item: i, ahora: ahora),
            Padding(padding: const EdgeInsets.only(right: 6), child: pie()),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.item, required this.ahora});

  final EnCurso item;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final i = item;
    final inicio = i.inicio;
    final lleva = inicio == null ? null : duracionCorta(ahora.difference(inicio).inSeconds);
    String? desde;
    if (inicio != null && i.fuente.toUpperCase() != "AIRFLOW") {
      final hhmm = "${inicio.hour.toString().padLeft(2, "0")}:${inicio.minute.toString().padLeft(2, "0")}";
      final esHoy = inicio.year == ahora.year && inicio.month == ahora.month && inicio.day == ahora.day;
      desde = esHoy ? "desde $hhmm" : "desde ${inicio.day}/${inicio.month} $hhmm";
    }
    final control = i.control;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: control == null ? null : () => mostrarDetalleProceso(context, control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(
                    [
                      i.fuente,
                      if (desde != null) desde,
                      if (i.pasos.isNotEmpty) "paso ${i.pasos.last}",
                      if (i.fueraDelMonitor) "fuera del monitor",
                    ].join(" · "),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              lleva ?? "en curso",
              style: theme.textTheme.labelLarge?.copyWith(
                color: StatusColors.info,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: control == null ? Colors.transparent : colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Punto azul que late: «esto está pasando ahora».
class _Pulso extends StatefulWidget {
  const _Pulso();

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
        decoration: const BoxDecoration(color: StatusColors.info, shape: BoxShape.circle),
      ),
    );
  }
}
