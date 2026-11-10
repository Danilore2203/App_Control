import "package:flutter/material.dart";

import "../models/netezza_bloqueos.dart";
import "../theme.dart";
import "../utils/sql_resumen.dart";
import "fondo_app.dart";
import "infra_comun.dart";
import "titulo_seccion.dart";

const _frase = {"exclusivo": "acceso exclusivo", "escritura": "escritura", "inserción": "inserción", "lectura": "lectura"};
String _acceso(String a) => _frase[a] ?? a;
String _plural(int n, String uno, String varios) => "$n ${n == 1 ? uno : varios}";

/// «Bloqueos y consultas trabadas» de Netezza, como en el monitor web:
/// quien frena a quien (y por que tabla), las que no avanzan, las que estan
/// en cola y quien ocupa el turno, las que esperan sin culpable a la vista,
/// y las transacciones abiertas. Administradores: abortar o matar.
///
/// Es un bloque (Column), no una lista: va dentro de la vista de Netezza,
/// arriba de las sesiones.
class BloqueosNetezzaVista extends StatelessWidget {
  const BloqueosNetezzaVista({
    super.key,
    required this.datos,
    this.actualizando = false,
    this.onAbortar,
    this.onMatar,
  });

  final BloqueosNetezza datos;
  final bool actualizando;
  final ValueChanged<SesionBloqueo>? onAbortar;
  final ValueChanged<SesionBloqueo>? onMatar;

  @override
  Widget build(BuildContext context) {
    final d = datos;
    final minimo = d.esperaMinS;
    final hijos = <Widget>[
      _Encabezado(datos: d, actualizando: actualizando),
      const SizedBox(height: 14),
    ];

    FilaBloqueo fila(SesionBloqueo s, {required String tiempo, required String etiqueta, required Color tono,
            String? insignia, String? causa, String? ayuda, String? nota, bool paso = false, List<SesionBloqueo>? varias}) =>
        FilaBloqueo(
          sesion: s,
          tiempo: tiempo,
          etiqueta: etiqueta,
          tono: tono,
          insignia: insignia,
          causa: causa,
          ayuda: ayuda,
          nota: nota,
          paso: paso,
          varias: varias,
          onAbortar: onAbortar,
          onMatar: onMatar,
        );

    // 1. Quien frena a quien.
    if (d.bloqueos.isNotEmpty) {
      hijos.add(_Seccion(
        titulo: "Sesiones que frenan a otras",
        cantidad: d.bloqueos.length,
        tono: StatusColors.critico,
        hijos: [
          for (final g in d.bloqueos)
            _Grupo(
              tono: g.bloqueadora.tambienEspera ? StatusColors.advertencia : StatusColors.critico,
              cabeza: fila(
                g.bloqueadora,
                tiempo: duracionCorta(g.bloqueadora.segundos),
                etiqueta: g.bloqueadora.estado == "tx-idle"
                    ? "tx abierta"
                    : (g.bloqueadora.tambienEspera ? "también espera" : "corriendo"),
                tono: g.bloqueadora.tambienEspera ? StatusColors.advertencia : StatusColors.critico,
                insignia: "Frena a ${_plural(g.esperan.length, "sesión", "sesiones")}",
                causa: g.bloqueadora.estado == "tx-idle"
                    ? "Transacción abierta sin hacer nada"
                    : (g.bloqueadora.tambienEspera ? "Ella también espera" : null),
                ayuda: g.bloqueadora.estado == "tx-idle"
                    ? "Retiene la tabla hasta que alguien haga COMMIT o ROLLBACK. Abortar su transacción la suelta."
                    : "Las que llegan después quedan detrás de ella.",
              ),
              ramas: [
                for (final w in g.esperan)
                  fila(
                    w,
                    tiempo: w.segundosMedidos >= minimo ? duracionCorta(w.segundos) : "recién",
                    etiqueta: "esperando",
                    tono: StatusColors.advertencia,
                    causa: w.choque.isEmpty ? null : "Pide ${_acceso(w.choque.first.pide)} a ${w.choque.first.tablaCorta}",
                    ayuda: w.choque.isEmpty
                        ? null
                        : "La sesión ${g.bloqueadora.sessionId} tiene ${w.choque.first.tabla} con ${_acceso(w.choque.first.retiene)}.",
                  ),
              ],
            ),
        ],
      ));
    }

    Widget filaTrabada(List<SesionBloqueo> grupo) {
      final t = grupo.first;
      final (tiempo, etiqueta, tono) = switch (t.tipo) {
        "sin_avance" => (duracionCorta(t.quietaS), "sin avanzar", StatusColors.critico),
        "en_cola" => (duracionCorta(t.segundos), "en cola", StatusColors.advertencia),
        "cliente" => (duracionCorta(t.segundos), "sin consulta", StatusColors.info),
        _ => (duracionCorta(t.correS), "corriendo", Theme.of(context).colorScheme.outline),
      };
      final (causa, ayuda) = _causaTrabada(t);
      return fila(t,
          tiempo: tiempo,
          etiqueta: etiqueta,
          tono: tono,
          causa: causa,
          ayuda: ayuda,
          paso: t.tipo == "sin_avance" || t.tipo == "larga",
          varias: grupo.length > 1 ? grupo : null);
    }

    // 2. Corren y no avanzan.
    final noAvanzan = d.noAvanzan;
    if (noAvanzan.isNotEmpty) {
      hijos.add(_Seccion(
        titulo: "No avanzan",
        cantidad: noAvanzan.length,
        pista: "Corren hace más de ${duracionCorta(d.largaMinS)} sin cambiar de paso.",
        tono: StatusColors.critico,
        hijos: [for (final g in agruparTrabadas(noAvanzan)) _Tarjeta(child: filaTrabada(g))],
      ));
    }

    // 3. En cola, y quien ocupa el turno.
    final enCola = d.enCola;
    if (enCola.isNotEmpty) {
      hijos.add(_Seccion(
        titulo: "En cola",
        cantidad: enCola.length,
        pista: "Netezza está lleno y no las deja empezar.",
        tono: StatusColors.advertencia,
        hijos: [
          for (final g in agruparTrabadas(enCola)) _Tarjeta(child: filaTrabada(g)),
          if (d.ocupan.isNotEmpty) ...[
            const _Subtitulo(icono: Icons.hourglass_top_rounded, texto: "Ocupan el turno ahora (las más pesadas que corren)"),
            for (final s in d.ocupan)
              _Tarjeta(
                child: fila(s, tiempo: duracionCorta(s.correS), etiqueta: "corriendo", tono: StatusColors.info),
              ),
          ],
        ],
      ));
    }

    // 4. Esperan un bloqueo y no se ve quien.
    if (d.esperandoSinCausa.isNotEmpty) {
      hijos.add(_Seccion(
        titulo: "Esperan sin culpable a la vista",
        cantidad: d.esperandoSinCausa.length,
        tono: StatusColors.advertencia,
        hijos: [
          for (final w in d.esperandoSinCausa)
            _Grupo(
              tono: Theme.of(context).colorScheme.outline,
              cabeza: fila(
                w,
                tiempo: w.segundosMedidos >= minimo ? duracionCorta(w.segundos) : "recién",
                etiqueta: "esperando",
                tono: StatusColors.advertencia,
                causa: w.tablas.isEmpty ? "Espera un bloqueo" : "Pide ${_acceso(w.tablas.first.acceso)} a ${w.tablas.first.tablaCorta}",
                ayuda: "Ninguna sesión visible usa esa tabla ahora: la que la frena pudo tocarla antes en su transacción."
                    "${w.posibles.isEmpty ? "" : " Abajo, las posibles."}",
              ),
              ramas: [
                for (final p in w.posibles)
                  p.estado == "tx-idle"
                      ? fila(p,
                          tiempo: duracionCorta(p.segundos),
                          etiqueta: "tx abierta",
                          tono: StatusColors.info,
                          causa: "Posible: transacción abierta")
                      : fila(p,
                          tiempo: (p.conntime ?? "").length >= 16 ? p.conntime!.substring(11, 16) : "—",
                          etiqueta: "conectada",
                          tono: Theme.of(context).colorScheme.outline,
                          causa: "Posible: misma base, desde antes",
                          ayuda: "Pudo tocar la tabla antes en su transacción."),
              ],
            ),
        ],
      ));
    }

    // 5. Informativo, plegado.
    final largas = d.largas;
    if (largas.isNotEmpty) {
      hijos.add(_Plegable(
        titulo: "Largas que siguen avanzando",
        cantidad: largas.length,
        pista: "Corren hace más de ${duracionCorta(d.largaMinS)}.",
        hijos: [for (final g in agruparTrabadas(largas)) _Tarjeta(child: filaTrabada(g))],
      ));
    }
    if (d.txAbiertas.isNotEmpty) {
      hijos.add(_Plegable(
        titulo: "Transacciones abiertas sin actividad",
        cantidad: d.txAbiertas.length,
        pista: "Frenan a quien pida sus tablas.",
        hijos: [
          for (final s in d.txAbiertas)
            _Tarjeta(
              child: fila(
                s,
                tiempo: duracionCorta(s.segundos),
                etiqueta: "tx abierta",
                tono: StatusColors.info,
                nota: s.tablas.isEmpty ? null : "Usa ${s.tablas.map((t) => "${t.tabla} (${_acceso(t.acceso)})").join(", ")}.",
              ),
            ),
        ],
      ));
    }

    if (d.todoEnOrden) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos);

    hijos.add(_Plegable(
      titulo: "Cómo se calcula",
      hijos: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            "El usuario del monitor no puede leer la tabla de bloqueos de Netezza, así que se deduce de las sesiones "
            "y del historial de consultas. Una sesión cuenta como esperando cuando lleva $minimo s sin poder empezar su consulta.\n\n"
            "«No avanzan»: corren hace más de ${duracionCorta(d.largaMinS)} y en ${duracionCorta(d.sinAvanceS)} no cambian de paso "
            "ni devuelven filas. Un paso pesado puede tardar eso y estar bien. Toca el chip de color para ver qué la frena.\n\n"
            "Se revisa sola cada 30 s mientras estás en la pestaña Netezza.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ),
      ],
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos);
  }

  static (String?, String?) _causaTrabada(SesionBloqueo t) {
    final r = t.resumen;
    final quien = t.esDataStage ? "DataStage" : "el cliente";
    final quienM = t.esDataStage ? "DataStage" : "El cliente";
    switch (t.tipo) {
      case "sin_avance":
        if (r.externa) {
          return (
            "Espera filas de $quien",
            "Netezza carga lo que le manda $quien. Si no avanza, el problema está en el job o en la base de origen, no en Netezza."
          );
        }
        if (r.descarga) return ("$quienM no lee el archivo", "Netezza ya tiene las filas y espera que $quien las reciba.");
        return (
          "Paso pesado sin terminar",
          "Un paso del plan lleva mucho: tabla grande, datos desbalanceados entre discos o estadísticas viejas."
        );
      case "en_cola":
        return ("Espera turno", "Netezza está lleno: arranca cuando termine alguna de las consultas que ocupan el turno.");
      case "cliente":
        return (
          "$quienM no avanza",
          "La sesión sigue activa pero Netezza no tiene nada corriendo para ella: el programa que la abrió está detenido o lee despacio."
        );
      default:
        return ("Avanza", "Sigue cambiando de paso.");
    }
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.datos, required this.actualizando});

  final BloqueosNetezza datos;
  final bool actualizando;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final d = datos;
    final alerta = d.alertas > 0;
    final tono = alerta ? StatusColors.critico : (d.todoEnOrden ? StatusColors.exitoso : StatusColors.info);
    final chips = <Widget>[];
    void add(int n, String uno, String varios, Color color, IconData icono) {
      if (n > 0) chips.add(PillEstado("$n ${n == 1 ? uno : varios}", color: color, icono: icono));
    }

    add(d.cuenta("esperando"), "esperando", "esperando", StatusColors.advertencia, Icons.hourglass_bottom_rounded);
    add(d.cuenta("bloqueadoras"), "la frena", "las frenan", StatusColors.critico, Icons.block_rounded);
    add(d.cuenta("sin_avance"), "sin avanzar", "sin avanzar", StatusColors.critico, Icons.pause_rounded);
    add(d.cuenta("en_cola"), "en cola", "en cola", StatusColors.advertencia, Icons.queue_rounded);
    add(d.cuenta("cliente"), "activa sin consulta", "activas sin consulta", StatusColors.info, Icons.person_off_outlined);
    add(d.cuenta("tx_abiertas"), "transacción abierta", "transacciones abiertas", StatusColors.info, Icons.lock_clock_outlined);
    add(d.cuenta("larga"), "larga que avanza", "largas que avanzan", colorScheme.outline, Icons.trending_up_rounded);

    final hora = (d.ahora ?? "").length >= 19 ? d.ahora!.substring(11, 19) : null;
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      borderColor: alerta ? StatusColors.critico.withValues(alpha: 0.45) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CajaIcono(
                alerta ? Icons.lock_outline_rounded : (d.todoEnOrden ? Icons.verified_outlined : Icons.lock_open_rounded),
                color: tono,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow("Netezza"),
                    const SizedBox(height: 2),
                    Text("Bloqueos y consultas trabadas", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (actualizando)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else if (hora != null)
                Text("Revisado $hora", style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          if (chips.isEmpty)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: StatusColors.exitoso, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Todo en orden: ninguna sesión espera por otra ni hay consultas trabadas.",
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
                  ),
                ),
              ],
            )
          else
            Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.cantidad, required this.hijos, required this.tono, this.pista});

  final String titulo;
  final int cantidad;
  final String? pista;
  final Color tono;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 4, height: 18, decoration: BoxDecoration(color: tono, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              PillEstado("$cantidad", color: tono),
            ],
          ),
          if (pista != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(pista!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
          const SizedBox(height: 10),
          for (final h in hijos) Padding(padding: const EdgeInsets.only(bottom: 10), child: h),
        ],
      ),
    );
  }
}

class _Plegable extends StatelessWidget {
  const _Plegable({required this.titulo, required this.hijos, this.cantidad, this.pista});

  final String titulo;
  final int? cantidad;
  final String? pista;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Vidrio(
        padding: EdgeInsets.zero,
        blur: 8,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            shape: const RoundedRectangleBorder(),
            collapsedShape: const RoundedRectangleBorder(),
            title: Row(
              children: [
                Expanded(child: Text(titulo, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                if (cantidad != null) PillEstado("$cantidad", color: colorScheme.outline),
              ],
            ),
            subtitle: pista == null
                ? null
                : Text(pista!, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
            children: [
              for (final h in hijos) Padding(padding: const EdgeInsets.only(bottom: 8), child: h),
            ],
          ),
        ),
      ),
    );
  }
}

/// La bloqueadora arriba y las que espera debajo, unidas por una linea.
class _Grupo extends StatelessWidget {
  const _Grupo({required this.cabeza, required this.ramas, required this.tono});

  final Widget cabeza;
  final List<Widget> ramas;
  final Color tono;

  @override
  Widget build(BuildContext context) {
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 4),
      blur: 10,
      borderColor: tono.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cabeza,
          if (ramas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 4),
              child: Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: tono.withValues(alpha: 0.5), width: 2))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final r in ramas) Padding(padding: const EdgeInsets.only(top: 8), child: r),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Vidrio(padding: const EdgeInsets.fromLTRB(12, 12, 6, 4), blur: 10, child: child);
  }
}

class _Subtitulo extends StatelessWidget {
  const _Subtitulo({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icono, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(texto, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Una sesion (o varias iguales) en una fila: cuanto lleva | que hace y quien | acciones.
class FilaBloqueo extends StatelessWidget {
  const FilaBloqueo({
    super.key,
    required this.sesion,
    required this.tiempo,
    required this.etiqueta,
    required this.tono,
    this.insignia,
    this.causa,
    this.ayuda,
    this.nota,
    this.paso = false,
    this.varias,
    this.onAbortar,
    this.onMatar,
  });

  final SesionBloqueo sesion;
  final String tiempo;
  final String etiqueta;
  final Color tono;
  final String? insignia;
  final String? causa;
  final String? ayuda;
  final String? nota;
  final bool paso;
  final List<SesionBloqueo>? varias;
  final ValueChanged<SesionBloqueo>? onAbortar;
  final ValueChanged<SesionBloqueo>? onMatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = sesion;
    final chips = <Widget>[
      if (varias != null)
        PillEstado("×${varias!.length} sesiones", color: colorScheme.outline, icono: Icons.copy_all_rounded)
      else
        ChipDato(Icons.tag_rounded, "Sesión ${s.sessionId}"),
      if (insignia != null) _Etiqueta(insignia!, color: StatusColors.critico, icono: Icons.block_rounded),
      if (causa != null)
        Tooltip(
          message: ayuda ?? "",
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 6),
          child: _Etiqueta(causa!, color: tono, icono: Icons.info_outline_rounded),
        ),
      if (paso && s.pasos > 0) _Paso(sesion: s),
      if (chipCosto(s.costo) != null) chipCosto(s.costo)!,
      if ((s.username ?? "").isNotEmpty) ChipDato(Icons.person_outline_rounded, s.username!, tooltip: "Usuario de la base"),
      if ((s.ipaddr ?? "").isNotEmpty) ChipDato(Icons.lan_outlined, s.ipaddr!, tooltip: "IP del cliente"),
      if (s.esDataStage) const ChipDato(Icons.settings_suggest_outlined, "DataStage", tooltip: "Usuario del sistema operativo: dsadm"),
      if (s.usuarioSo != null) ChipDato(Icons.badge_outlined, s.usuarioSo!, tooltip: "Usuario del sistema operativo"),
      if (s.dagId != null)
        ChipDato(Icons.account_tree_outlined, "${s.dagId}${s.taskId == null ? "" : " / ${s.taskId}"}",
            color: StatusColors.info, tooltip: "DAG de Airflow que abrió la sesión"),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tiempo,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium?.copyWith(color: tono, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                  Text(etiqueta, style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LineaSql(s.command, tono: tono),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: chips),
                    if (nota != null) ...[
                      const SizedBox(height: 6),
                      Text(nota!, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.35)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        // Wrap: en pantallas angostas los botones pasan a la linea de abajo.
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            BotonAccion(
              icono: Icons.code_rounded,
              texto: "Ver consulta",
              onTap: () => mostrarConsulta(
                context,
                titulo: varias != null ? "${varias!.length} sesiones con la misma consulta" : "Sesión ${s.sessionId}",
                subtitulo: [s.username, s.dbname, s.ipaddr].whereType<String>().join(" · "),
                sql: s.command,
              ),
            ),
            if (varias != null && (onAbortar != null || onMatar != null))
              BotonAccion(
                icono: Icons.list_alt_rounded,
                texto: "Sesiones",
                onTap: () => _elegirSesion(context, varias!),
              )
            else ...[
              if (onAbortar != null)
                BotonAccion(icono: Icons.undo_rounded, texto: "Abortar", color: StatusColors.advertencia, onTap: () => onAbortar!(s)),
              if (onMatar != null)
                BotonAccion(icono: Icons.cancel_outlined, texto: "Matar", color: StatusColors.critico, onTap: () => onMatar!(s)),
            ],
          ],
        ),
      ],
    );
  }

  /// Varias sesiones con la misma consulta: elegir sobre cual actuar.
  void _elegirSesion(BuildContext context, List<SesionBloqueo> lista) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (hoja) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text("${lista.length} sesiones con la misma consulta",
                style: Theme.of(hoja).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final x in lista)
              Row(
                children: [
                  Expanded(
                    child: Text("Sesión ${x.sessionId}",
                        style: AppTextStyles.tech(color: Theme.of(hoja).colorScheme.onSurface, fontSize: 12.5, letterSpacing: 0.3)),
                  ),
                  if (onAbortar != null)
                    IconButton(
                      tooltip: "Abortar transacción",
                      icon: const Icon(Icons.undo_rounded, color: StatusColors.advertencia),
                      onPressed: () {
                        Navigator.of(hoja).pop();
                        onAbortar!(x);
                      },
                    ),
                  if (onMatar != null)
                    IconButton(
                      tooltip: "Matar sesión",
                      icon: const Icon(Icons.cancel_outlined, color: StatusColors.critico),
                      onPressed: () {
                        Navigator.of(hoja).pop();
                        onMatar!(x);
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Como PillEstado pero el texto puede ocupar dos lineas (causas largas en pantallas angostas).
class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, {required this.color, required this.icono});

  final String texto;
  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800, height: 1.3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text.rich(
        TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icono, size: 12, color: color)),
          ),
          TextSpan(text: texto),
        ]),
        style: estilo,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.sesion});

  final SesionBloqueo sesion;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avance = sesion.pasos == 0 ? 0.0 : ((sesion.pasoActual - 1) / sesion.pasos).clamp(0.0, 1.0);
    return Tooltip(
      message: "Paso ${sesion.pasoActual} de ${sesion.pasos} del plan",
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 42, child: BarraProgreso(valor: avance, color: acentoTinta(context), alto: 4)),
            const SizedBox(width: 6),
            Text(
              "paso ${sesion.pasoActual}/${sesion.pasos}",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
