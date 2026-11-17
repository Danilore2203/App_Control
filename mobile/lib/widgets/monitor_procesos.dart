import "package:flutter/material.dart";

import "../models/control.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "corriendo_ahora.dart";
import "fondo_app.dart";
import "titulo_seccion.dart";

/// La vista Procesos de la app como el «Monitor de procesos» de la web
/// (/procesos): contadores por estado, «Corriendo ahora», «Agenda del día»
/// por hora de fin esperada y la lista con el mismo «Filtro». Además de
/// DataStage y Pentaho trae los DAG de Airflow, con su opción en el filtro.

// ── Motor y versión ──────────────────────────────────────────────────────

/// ds117 / ds115 / ds150 según la versión del proceso (como _dsTargetFromRow).
String dsTargetDe(Control c) {
  final v = (c.version ?? "").trim();
  if (v == "11.7") return "ds117";
  if (v == "11.5") return "ds115";
  if (v.contains("150")) return "ds150";
  return "";
}

/// datastage, pentaho, airflow u other.
String motorDe(Control c) {
  final f = c.fuente.trim().toUpperCase();
  if (f.contains("PENTAHO")) return "pentaho";
  if (f.contains("AIRFLOW")) return "airflow";
  if (f.contains("DATASTAGE") || dsTargetDe(c).isNotEmpty) return "datastage";
  return "other";
}

bool esAirflow(Control c) => motorDe(c) == "airflow";

/// «DataStage 11.7», «Pentaho», «Airflow»...
String etiquetaMotor(Control c) {
  switch (motorDe(c)) {
    case "datastage":
      return switch (dsTargetDe(c)) {
        "ds117" => "DataStage 11.7",
        "ds115" => "DataStage 11.5",
        "ds150" => "DataStage 150",
        _ => "DataStage",
      };
    case "pentaho":
      return "Pentaho";
    case "airflow":
      return "Airflow";
    default:
      return c.fuente.trim().isEmpty ? "Otro" : c.fuente.trim();
  }
}

/// Opciones del «Filtro» de la lista, en el orden de la web, más «Solo Airflow».
const opcionesFiltroMotor = <(String, String)>[
  ("all", "Todos"),
  ("ds:ds117", "DataStage 11.7"),
  ("ds:ds150", "DataStage 150 vía 11.7"),
  ("ds:ds115", "DataStage 11.5"),
  ("ds:none", "Sin DataStage"),
  ("tech:pentaho", "Solo Pentaho"),
  ("tech:datastage", "Solo DataStage"),
  ("tech:airflow", "Solo Airflow"),
  ("tech:other", "Otros"),
];

String etiquetaFiltroMotor(String clave) =>
    opcionesFiltroMotor.firstWhere((o) => o.$1 == clave, orElse: () => opcionesFiltroMotor.first).$2;

bool cumpleFiltroMotor(String clave, Control c) {
  if (clave.startsWith("ds:")) {
    final t = clave.substring(3);
    return t == "none" ? dsTargetDe(c).isEmpty : dsTargetDe(c) == t;
  }
  if (clave.startsWith("tech:")) return motorDe(c) == clave.substring(5);
  return true;
}

/// La fuente del catálogo que corresponde al filtro, para lo que corre fuera
/// del monitor en «Corriendo ahora».
String? fuenteDelFiltroMotor(String clave) {
  if (clave == "tech:pentaho") return "PENTAHO";
  if (clave == "tech:airflow") return "AIRFLOW";
  if (clave == "tech:datastage" || (clave.startsWith("ds:") && clave != "ds:none")) return "DATASTAGE";
  return null;
}

// ── Estado (los contadores de la web) ─────────────────────────────────────

/// ok, err, delay, run o pend: OK, Error, Demorado, Actualizando, En proceso.
String tonoDe(Control c) => switch (c.categoria) {
      "green" => "ok",
      "red" => "err",
      "orange" => "delay",
      "blue" => "run",
      _ => "pend",
    };

const tonos = ["ok", "err", "delay", "run", "pend"];

String etiquetaTono(String tono) => switch (tono) {
      "ok" => "OK",
      "err" => "Error",
      "delay" => "Demorado",
      "run" => "Actualizando",
      "pend" => "En proceso",
      "corriendo" => "Corriendo",
      _ => tono,
    };

Color colorTono(String tono) => switch (tono) {
      "ok" => StatusColors.exitoso,
      "err" => StatusColors.critico,
      "delay" => StatusColors.advertencia,
      "run" => StatusColors.info,
      _ => StatusColors.neutral,
    };

/// Turquesa de «Corriendo» en la web (--pr-run), distinto del azul de «Actualizando».
Color colorCorriendo(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFF67E8F9) : const Color(0xFF0E7490);

/// Corre ahora: OP lo ve en DataStage/Pentaho, o es un DAG de Airflow en ejecución.
bool estaCorriendo(Control c, Map<String, Map<String, dynamic>> enVivo) =>
    enVivo.containsKey(c.nombre.toUpperCase()) || (esAirflow(c) && c.categoria == "blue");

/// Lo que OP ve corriendo, por nombre en mayúsculas.
Map<String, Map<String, dynamic>> enVivoPorNombre(CorriendoEnVivo? vivo) => {
      for (final p in vivo?.procesos ?? const <Map<String, dynamic>>[])
        if ((p["nombre"] ?? "").toString().isNotEmpty) p["nombre"].toString().toUpperCase(): p,
    };

// ── Horas ─────────────────────────────────────────────────────────────────

/// Hora de fin esperada (HORA_FIN de DataStage/Pentaho, «10:03:00»): la
/// columna de la lista y la agenda de la web. Airflow no tiene: su hora_fin es
/// cuando terminó la última corrida.
({int h, int m})? horaEsperada(Control c) {
  if (esAirflow(c)) return null;
  final m = RegExp(r"^(\d{1,2}):(\d{2})").firstMatch((c.horaFin ?? "").trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return (h: h, m: mi);
}

String _dos(int n) => n.toString().padLeft(2, "0");

/// Lo que va a la derecha de la fila: la hora de fin esperada; en Airflow,
/// cuándo terminó (o empezó, si corre) su última corrida, en hora del celular.
String horaDeFila(Control c, DateTime ahora) {
  final h = horaEsperada(c);
  if (h != null) return "${_dos(h.h)}:${_dos(h.m)}";
  if (esAirflow(c)) {
    final fin = (c.horaFin ?? "").trim();
    final f = fechaAirflowLocal(c.categoria == "blue" || fin.isEmpty ? c.horaLog : fin, ahora);
    if (f != null) {
      final hoy = f.year == ahora.year && f.month == ahora.month && f.day == ahora.day;
      return hoy ? "${_dos(f.hour)}:${_dos(f.minute)}" : "${_dos(f.day)}/${_dos(f.month)}";
    }
    final p = RegExp(r"^(\d{1,2}):(\d{2})").firstMatch((c.horaProgramada ?? "").trim());
    if (p != null) return "prog. ${p.group(1)!.padLeft(2, "0")}:${p.group(2)}";
  }
  return "—";
}

/// Como la web (ORDER BY hora): DataStage y Pentaho por hora de fin esperada;
/// después Airflow, por cuándo terminó su última corrida.
List<Control> ordenarComoLaWeb(List<Control> controles) {
  int minutos(Control c) {
    final h = horaEsperada(c);
    return h == null ? 24 * 60 : h.h * 60 + h.m;
  }

  String finAirflow(Control c) {
    final f = (c.horaFin ?? "").trim();
    return f.isNotEmpty ? f : (c.horaLog ?? "").trim();
  }

  final lista = [...controles];
  lista.sort((a, b) {
    final ga = esAirflow(a) ? 1 : 0, gb = esAirflow(b) ? 1 : 0;
    if (ga != gb) return ga - gb;
    if (ga == 0) {
      final d = minutos(a) - minutos(b);
      return d != 0 ? d : a.nombre.compareTo(b.nombre);
    }
    final fa = finAirflow(a), fb = finAirflow(b);
    if (fa.isEmpty != fb.isEmpty) return fa.isEmpty ? 1 : -1;
    final d = fa.compareTo(fb);
    return d != 0 ? d : a.nombre.compareTo(b.nombre);
  });
  return lista;
}

// ── Agenda del día ────────────────────────────────────────────────────────

class AgendaCalculada {
  AgendaCalculada(this.horas, this.sinHora);

  /// 24 horas: por cada una, cuántos hay de cada tono.
  final List<Map<String, int>> horas;

  /// DataStage/Pentaho sin hora de fin esperada (Airflow no se cuenta).
  final int sinHora;

  int totalDe(int h) => horas[h].values.fold(0, (s, n) => s + n);
}

AgendaCalculada calcularAgenda(List<Control> controles) {
  final horas = List.generate(24, (_) => <String, int>{});
  var sinHora = 0;
  for (final c in controles) {
    if (esAirflow(c)) continue;
    final h = horaEsperada(c);
    if (h == null) {
      sinHora++;
      continue;
    }
    final t = tonoDe(c);
    horas[h.h][t] = (horas[h.h][t] ?? 0) + 1;
  }
  return AgendaCalculada(horas, sinHora);
}

/// Los próximos cierres esperados que siguen pendientes o actualizándose.
List<({int h, int m, String nombre})> proximosCierres(List<Control> controles, DateTime ahora, {int n = 3}) {
  final mAhora = ahora.hour * 60 + ahora.minute;
  final lista = <({int h, int m, String nombre})>[];
  for (final c in controles) {
    final h = horaEsperada(c);
    final t = tonoDe(c);
    if (h == null || (t != "pend" && t != "run")) continue;
    if (h.h * 60 + h.m < mAhora) continue;
    lista.add((h: h.h, m: h.m, nombre: c.nombre));
  }
  lista.sort((a, b) => (a.h * 60 + a.m) - (b.h * 60 + b.m));
  return lista.take(n).toList();
}

class AgendaDelDia extends StatelessWidget {
  const AgendaDelDia({
    super.key,
    required this.controles,
    required this.ahora,
    this.horaActiva,
    this.onHora,
  });

  final List<Control> controles;
  final DateTime ahora;
  final int? horaActiva;

  /// Tocar una hora filtra la lista; tocarla otra vez quita el filtro (null).
  final ValueChanged<int?>? onHora;

  static const _ordenSegmentos = ["pend", "run", "err", "delay", "ok"]; // de arriba a abajo

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final agenda = calcularAgenda(controles);
    final maximo = [for (var h = 0; h < 24; h++) agenda.totalDe(h)].fold(1, (a, b) => a > b ? a : b);
    final prox = proximosCierres(controles, ahora);
    final hayAirflow = controles.any(esAirflow);
    final pista = [
      prox.isEmpty
          ? "No queda nada pendiente para hoy"
          : "Próximos cierres esperados: ${prox.map((p) => "${_dos(p.h)}:${_dos(p.m)} ${p.nombre}").join("  ·  ")}",
      if (agenda.sinHora > 0) "${agenda.sinHora} sin hora",
      if (horaActiva != null) "filtrando ${_dos(horaActiva!)}:00",
    ].join("  ·  ");

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Vidrio(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Agenda del día", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(
              pista,
              key: const Key("agenda_pista"),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.3),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 104,
              child: LayoutBuilder(
                builder: (context, limites) {
                  final fraccion = (ahora.hour + ahora.minute / 60) / 24;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var h = 0; h < 24; h++)
                            Expanded(
                              child: _HoraAgenda(
                                key: Key("agenda_hora_$h"),
                                hora: h,
                                conteo: agenda.horas[h],
                                total: agenda.totalDe(h),
                                maximo: maximo,
                                pasada: h < ahora.hour,
                                actual: h == ahora.hour,
                                activa: horaActiva == h,
                                onTap: onHora == null || agenda.totalDe(h) == 0
                                    ? null
                                    : () => onHora!(horaActiva == h ? null : h),
                              ),
                            ),
                        ],
                      ),
                      // Marca de «ahora».
                      Positioned(
                        left: (fraccion * limites.maxWidth - 0.75).clamp(0.0, limites.maxWidth - 1.5),
                        top: 14,
                        bottom: 16,
                        child: IgnorePointer(
                          child: Container(width: 1.5, color: StatusColors.critico.withValues(alpha: 0.8)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final t in ["ok", "delay", "err", "run", "pend"])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: colorTono(t), borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 4),
                      Text(etiquetaTono(t),
                          style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                if (hayAirflow)
                  Text("Airflow no entra: no tiene hora esperada",
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HoraAgenda extends StatelessWidget {
  const _HoraAgenda({
    super.key,
    required this.hora,
    required this.conteo,
    required this.total,
    required this.maximo,
    required this.pasada,
    required this.actual,
    required this.activa,
    this.onTap,
  });

  final int hora;
  final Map<String, int> conteo;
  final int total;
  final int maximo;
  final bool pasada;
  final bool actual;
  final bool activa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final alto = total == 0 ? 0.0 : (total / maximo).clamp(0.08, 1.0);
    final etiqueta = theme.textTheme.labelSmall?.copyWith(
      fontSize: 8.5,
      fontWeight: activa || actual ? FontWeight.w800 : FontWeight.w600,
      color: activa ? acentoTinta(context) : (actual ? colorScheme.onSurface : colorScheme.outline),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: onTap != null,
      selected: activa,
      label: "${_dos(hora)}:00, $total proceso${total == 1 ? "" : "s"}",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: activa
              ? BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: Column(
            children: [
              SizedBox(
                height: 14,
                child: total == 0
                    ? null
                    : FittedBox(fit: BoxFit.scaleDown, child: Text("$total", style: etiqueta)),
              ),
              Expanded(
                child: Opacity(
                  opacity: pasada && !activa ? 0.6 : 1,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: total == 0
                        ? Container(height: 2, color: colorScheme.outlineVariant.withValues(alpha: 0.5))
                        : FractionallySizedBox(
                            heightFactor: alto,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final t in AgendaDelDia._ordenSegmentos)
                                    if ((conteo[t] ?? 0) > 0) Expanded(flex: conteo[t]!, child: ColoredBox(color: colorTono(t))),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 16,
                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Text(_dos(hora), style: etiqueta))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Contadores ────────────────────────────────────────────────────────────

/// OK, Error, Demorado, Actualizando, En proceso y Corriendo, como la fila de
/// contadores de la web. Tocar uno filtra la lista; tocarlo otra vez lo quita.
class ContadoresProcesos extends StatelessWidget {
  const ContadoresProcesos({
    super.key,
    required this.controles,
    required this.corriendo,
    this.subCorriendo,
    this.subCorriendoAviso = false,
    this.seleccionado,
    this.onSeleccionar,
  });

  final List<Control> controles;

  /// Cuántos corren ahora (null: todavía no se sabe).
  final int? corriendo;
  final String? subCorriendo;
  final bool subCorriendoAviso;
  final String? seleccionado;
  final ValueChanged<String?>? onSeleccionar;

  static const _iconos = {
    "ok": Icons.check_rounded,
    "err": Icons.close_rounded,
    "delay": Icons.hourglass_bottom_rounded,
    "run": Icons.sync_rounded,
    "pend": Icons.settings_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cuenta = {for (final t in tonos) t: 0};
    for (final c in controles) {
      final t = tonoDe(c);
      cuenta[t] = (cuenta[t] ?? 0) + 1;
    }
    Widget tile(String clave, String valor, Color color, IconData icono, {String? sub, bool aviso = false}) =>
        Expanded(
          child: _Contador(
            key: Key("contador_$clave"),
            etiqueta: etiquetaTono(clave),
            valor: valor,
            color: color,
            icono: icono,
            sub: sub,
            subAviso: aviso,
            elegido: seleccionado == clave,
            onTap: onSeleccionar == null ? null : () => onSeleccionar!(seleccionado == clave ? null : clave),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in ["ok", "err", "delay"]) ...[
                  if (t != "ok") const SizedBox(width: 8),
                  tile(t, "${cuenta[t]}", colorTono(t), _iconos[t]!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tile("run", "${cuenta["run"]}", colorTono("run"), _iconos["run"]!),
                const SizedBox(width: 8),
                tile("pend", "${cuenta["pend"]}", colorTono("pend"), _iconos["pend"]!),
                const SizedBox(width: 8),
                tile("corriendo", corriendo == null ? "—" : "$corriendo", colorCorriendo(context),
                    Icons.play_circle_outline_rounded,
                    sub: subCorriendo, aviso: subCorriendoAviso),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.color,
    required this.icono,
    this.sub,
    this.subAviso = false,
    this.elegido = false,
    this.onTap,
  });

  final String etiqueta;
  final String valor;
  final Color color;
  final IconData icono;
  final String? sub;
  final bool subAviso;
  final bool elegido;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      selected: elegido,
      button: onTap != null,
      child: Material(
        color: elegido ? color.withValues(alpha: 0.14) : colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: elegido ? color : colorScheme.outlineVariant, width: elegido ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(icono, size: 15, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        valor,
                        maxLines: 1,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          letterSpacing: -0.6,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      // «Actualizando» no entra entero en un celular angosto: se achica, no se corta.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          etiqueta,
                          maxLines: 1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (sub != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          sub!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            height: 1.2,
                            color: subAviso ? StatusColors.advertencia : colorScheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Fila de la lista ──────────────────────────────────────────────────────

/// Fila de la lista como la tabla de la web: punto de estado, nombre (con la
/// marca de que corre ahora) y la hora; abajo el motor y el estado.
class FilaProceso extends StatelessWidget {
  const FilaProceso({
    super.key,
    required this.control,
    required this.ahora,
    this.enVivo,
    this.primera = false,
    this.ultima = false,
    this.onTap,
  });

  final Control control;
  final DateTime ahora;

  /// Lo que OP ve corriendo de este proceso (desde, hoy), si corre.
  final Map<String, dynamic>? enVivo;
  final bool primera;
  final bool ultima;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tono = tonoDe(control);
    final color = colorTono(tono);
    final core = control.core?.trim().toLowerCase() == "si";
    final corre = enVivo != null || (esAirflow(control) && control.categoria == "blue");
    final viejo = enVivo != null && enVivo!["hoy"] == false;
    final desde = (enVivo?["desde"] ?? "").toString();
    const radio = Radius.circular(OpTokens.radius);
    final turquesa = colorCorriendo(context);

    return Material(
      color: tono == "err"
          ? Color.alphaBlend(color.withValues(alpha: 0.06), colorScheme.surfaceContainerHigh)
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.vertical(
        top: primera ? radio : Radius.zero,
        bottom: ultima ? radio : Radius.zero,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: primera ? radio : Radius.zero,
          bottom: ultima ? radio : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            border: ultima ? null : Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
          ),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            control.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                          ),
                        ),
                        if (core) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.bolt_rounded, size: 14, color: StatusColors.critico, semanticLabel: "core"),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${etiquetaMotor(control)} · ${etiquetaTono(tono)}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.2),
                    ),
                  ],
                ),
              ),
              if (corre) ...[
                const SizedBox(width: 6),
                _ChipCorre(
                  texto: desde.isEmpty ? "corriendo" : desde,
                  color: viejo ? StatusColors.advertencia : turquesa,
                ),
              ],
              const SizedBox(width: 8),
              Text(
                horaDeFila(control, ahora),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipCorre extends StatelessWidget {
  const _ChipCorre({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(
            texto,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Hoja con las opciones del «Filtro» (con cuántos hay en cada una) y «Solo
/// core». Devuelve la clave elegida, «core» si se cambió «Solo core», o null.
Future<String?> elegirFiltroMotor(
  BuildContext context, {
  required List<Control> controles,
  required String actual,
  required bool soloCore,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final base = soloCore ? controles.where((c) => c.core?.trim().toLowerCase() == "si").toList() : controles;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text("Filtro", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            SwitchListTile(
              key: const Key("filtro_solo_core"),
              value: soloCore,
              onChanged: (_) => Navigator.of(context).pop("core"),
              secondary: const Icon(Icons.bolt_rounded, color: StatusColors.critico),
              title: const Text("Solo procesos core"),
            ),
            const Divider(height: 8),
            for (final (clave, etiqueta) in opcionesFiltroMotor)
              ListTile(
                key: Key("filtro_$clave"),
                dense: true,
                title: Text(etiqueta,
                    style: TextStyle(fontWeight: clave == actual ? FontWeight.w800 : FontWeight.w500)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("${base.where((c) => cumpleFiltroMotor(clave, c)).length}",
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(width: 8),
                    Icon(clave == actual ? Icons.check_rounded : null, size: 20, color: acentoTinta(context)),
                  ],
                ),
                onTap: () => Navigator.of(context).pop(clave),
              ),
          ],
        ),
      );
    },
  );
}
