import "package:flutter/material.dart";

import "../services/comandos_service.dart";
import "../services/robby_service.dart";
import "../services/sesion_actual.dart";
import "../theme.dart";
import "../utils/formato.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/indicador_ejecucion.dart";
import "../widgets/titulo_seccion.dart";

/// Robby, como el modal de /procesos en la web (solo administradores):
/// consultar un proceso (si figura lanzado en Robby y si está en la tabla de
/// flujos ALFA de Netezza) e insertarlo en esa tabla para que Robby lo corra.
class RobbyScreen extends StatefulWidget {
  const RobbyScreen({super.key, this.procesoInicial, this.servicio});

  final String? procesoInicial;

  /// Para las pruebas; normalmente null.
  final RobbyService? servicio;

  @override
  State<RobbyScreen> createState() => _RobbyScreenState();
}

class _RobbyScreenState extends State<RobbyScreen> {
  late final RobbyService _servicio = widget.servicio ?? RobbyService();
  final _proceso = TextEditingController();
  final _nombreInsert = TextEditingController();

  VerificacionRobby? _verificacion;
  bool _consultando = false;
  bool _insertando = false;
  String? _error;
  String? _resultadoInsert;
  bool _insertOk = false;

  @override
  void initState() {
    super.initState();
    _nombreInsert.addListener(() => setState(() {}));
    final inicial = widget.procesoInicial?.trim() ?? "";
    // Sin permisos no se pide nada (el backend lo rechazaria igual).
    if (inicial.isNotEmpty && SesionActual.esAdmin) {
      _proceso.text = inicial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _consultar());
    }
  }

  @override
  void dispose() {
    _proceso.dispose();
    _nombreInsert.dispose();
    super.dispose();
  }

  String _mensaje(Object e) => e is ComandoFallidoException ? e.mensaje : e.toString().replaceFirst("Exception: ", "");

  Future<void> _consultar() async {
    final p = _proceso.text.trim();
    if (p.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _consultando = true;
      _error = null;
      _resultadoInsert = null;
    });
    try {
      final v = await _servicio.verificar(p);
      if (!mounted) return;
      setState(() {
        _verificacion = v;
        _nombreInsert.text = v.sugerencia ?? "";
      });
    } catch (e) {
      if (mounted) setState(() => _error = _mensaje(e));
    } finally {
      if (mounted) setState(() => _consultando = false);
    }
  }

  Future<void> _insertar() async {
    final nombre = _nombreInsert.text.trim();
    if (!RobbyService.nombreValido.hasMatch(nombre)) return;
    final yaEnAlfa = _verificacion?.enAlfa ?? false;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("¿Insertar $nombre en Robby?"),
        content: Text(
          "Se agrega una fila en la tabla de flujos ALFA de Netezza y Robby lo va a ejecutar, "
          "igual que «Ejecutar insert» en la web.${yaEnAlfa ? "\n\nOjo: ya figura en ALFA; insertarlo de nuevo lo vuelve a correr." : ""}",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Insertar")),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() {
      _insertando = true;
      _resultadoInsert = null;
    });
    try {
      final cuando = await _servicio.insertar(nombre, titulo: "Insertar $nombre en Robby");
      if (!mounted) return;
      final hora = fechaCatalogo(cuando);
      setState(() {
        _insertOk = true;
        _resultadoInsert = "Insertado en Robby${hora == null ? "" : " ($hora)"}. Robby lo toma en su próxima pasada.";
      });
      await _consultar(); // para ver la fila nueva en ALFA
      if (mounted) {
        setState(() {
          _insertOk = true;
          _resultadoInsert = "Insertado en Robby${hora == null ? "" : " ($hora)"}. Robby lo toma en su próxima pasada.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _insertOk = false;
          _resultadoInsert = _mensaje(e);
        });
      }
    } finally {
      if (mounted) setState(() => _insertando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (!SesionActual.esAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text("Robby")),
        body: EstadoVacio(
          icono: Icons.lock_outline_rounded,
          mensaje: "Solo administradores",
          detalle: "Robby está disponible solo para administradores.",
          colorIcono: colorScheme.onSurfaceVariant,
        ),
      );
    }
    final v = _verificacion;
    final nombre = _nombreInsert.text.trim();
    final nombreOk = RobbyService.nombreValido.hasMatch(nombre);
    return Scaffold(
      appBar: AppBar(title: const Text("Robby")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          MensajeInline(
            "Robby ejecuta los procesos que están en la tabla de flujos ALFA de Netezza. Consulta el proceso y, "
            "si hace falta, insértalo para que Robby lo corra.",
            color: colorScheme.primary,
            icono: Icons.info_outline,
          ),
          const SizedBox(height: 14),
          const Eyebrow("Proceso (LOG)"),
          const SizedBox(height: 6),
          TextField(
            key: const Key("robby_proceso"),
            controller: _proceso,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _consultar(),
            decoration: InputDecoration(
              hintText: "JOB_..._LOG_ALL",
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _consultando
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      key: const Key("robby_consultar"),
                      tooltip: "Consultar",
                      onPressed: _consultar,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            MensajeInline(_error!),
          ],
          if (v != null) ...[
            const SizedBox(height: 16),
            if (v.sinProcesoPadre) ...[
              const MensajeInline(
                "Robby: sin relación padre (SIN RELACION). Proceso ya programado.",
                color: StatusColors.advertencia,
                icono: Icons.warning_amber_rounded,
              ),
              const SizedBox(height: 10),
            ],
            if (v.robbyError != null || v.alfaError != null) ...[
              MensajeInline(
                "Parcial: ${[
                  if (v.robbyError != null) "Robby: ${v.robbyError}",
                  if (v.alfaError != null) "ALFA: ${v.alfaError}",
                ].join(" · ")}",
                color: StatusColors.advertencia,
                icono: Icons.warning_amber_rounded,
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                const Eyebrow("Resultado"),
                const Spacer(),
                Text(
                  "Robby ${v.robbyFilas} · ALFA ${v.alfaFilas}",
                  style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.outline, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (v.filas.isEmpty)
              Text("Sin datos en Robby ni en ALFA para ese proceso.",
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline))
            else
              for (final f in v.filas) _FilaRobby(fila: f),
            const SizedBox(height: 18),
            const Eyebrow("Insertar en Robby"),
            const SizedBox(height: 4),
            Text(
              "Va el nombre del proceso padre (la columna «Proceso»), no el LOG *_ALL.",
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key("robby_nombre_insert"),
              controller: _nombreInsert,
              autocorrect: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.input_rounded),
                errorText: nombre.isNotEmpty && !nombreOk ? "Solo letras, números, _, -, ., / y espacios" : null,
              ),
            ),
            if (v.sqlInsert != null && nombre == v.sugerencia) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: SelectableText(
                  v.sqlInsert!,
                  style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 11.5, letterSpacing: 0.1),
                ),
              ),
            ],
            if (_resultadoInsert != null) ...[
              const SizedBox(height: 10),
              MensajeInline(
                _resultadoInsert!,
                color: _insertOk ? StatusColors.exitoso : null,
                icono: _insertOk ? Icons.check_circle_outline : Icons.error_outline,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                key: const Key("robby_insertar"),
                onPressed: _insertando || !nombreOk ? null : _insertar,
                icon: _insertando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.playlist_add_rounded),
                label: Text(_insertando ? "Insertando…" : "Insertar en Robby"),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: const SafeArea(child: IndicadorEjecucion()),
    );
  }
}

class _FilaRobby extends StatelessWidget {
  const _FilaRobby({required this.fila});

  final FilaRobby fila;

  Color _tono(ColorScheme cs) => switch (fila.estado.toUpperCase()) {
        "OK" => StatusColors.exitoso,
        "ERROR" => StatusColors.critico,
        "DEMORADO" => StatusColors.advertencia,
        "ACTUALIZANDO" => StatusColors.info,
        _ => cs.outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final f = fila;
    final alfa = [if (f.fechaEjecucion != null) f.fechaEjecucion!, if (f.hora != null) f.hora!].join(" ");
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _tono(cs).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(f.log.isEmpty ? "—" : f.log,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              if (f.estado.isNotEmpty) PillEstado(f.estado, color: _tono(cs)),
            ],
          ),
          const SizedBox(height: 4),
          if (f.nombreProceso.isNotEmpty)
            Text("Proceso: ${f.nombreProceso}", style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          Text(
            alfa.isEmpty ? "No figura en ALFA" : "En ALFA: ${fechaCatalogo(alfa) ?? alfa}",
            style: theme.textTheme.bodySmall?.copyWith(color: alfa.isEmpty ? StatusColors.advertencia : cs.onSurfaceVariant),
          ),
          if (f.alfaRutaPadre != null)
            Text(f.alfaRutaPadre!,
                style: AppTextStyles.tech(color: cs.outline, fontSize: 11, letterSpacing: 0.1)),
        ],
      ),
    );
  }
}
