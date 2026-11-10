import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../services/comandos_service.dart";
import "../theme.dart";
import "../utils/sql_resumen.dart";
import "titulo_seccion.dart";

/// Piezas compartidas de Infraestructura (sesiones de Netezza y PostgreSQL,
/// bloqueos): la consulta en pocas palabras, chips de datos, acciones y la
/// hoja con la consulta completa.

/// «Carga  FACT_VENTAS» con el verbo en una pastilla y la tabla en mono.
class LineaSql extends StatelessWidget {
  const LineaSql(this.comando, {super.key, this.tono});

  final String? comando;
  final Color? tono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final r = resumirSql(comando);
    if (r.verbo.isEmpty) {
      return Text(
        "Sin consulta en curso",
        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
      );
    }
    final color = tono ?? acentoTinta(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            r.verbo,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: r.tabla.isNotEmpty
              ? Text(
                  r.tabla,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tech(color: colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                )
              // Sin tabla reconocible: el comienzo de la consulta, mas tenue.
              : Text(
                  r.externa ? "tabla externa" : extractoSql(comando),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tech(
                      color: colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.1),
                ),
        ),
        if (r.temporal) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: "Tabla temporal de DataStage",
            child: Icon(Icons.layers_outlined, size: 15, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Dato chico con icono (usuario, IP, DAG, costo...).
class ChipDato extends StatelessWidget {
  const ChipDato(this.icono, this.texto, {super.key, this.color, this.tooltip});

  final IconData icono;
  final String texto;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tono = color ?? colorScheme.onSurfaceVariant;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color == null ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.55) : tono.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color == null ? colorScheme.outlineVariant.withValues(alpha: 0.6) : tono.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: tono),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color == null ? colorScheme.onSurface : tono,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return chip;
    return Tooltip(message: tooltip!, triggerMode: TooltipTriggerMode.tap, child: chip);
  }
}

/// Costo estimado de Netezza con los colores del monitor web (alto / critico).
Widget? chipCosto(num? costo) {
  if (costo == null || costo <= 0) return null;
  final color = costo >= costoCritico
      ? StatusColors.critico
      : costo >= costoAlto
          ? StatusColors.advertencia
          : null;
  return ChipDato(Icons.speed_rounded, "Costo ${costoCorto(costo)}", color: color, tooltip: "Costo estimado: ${costo.round()}");
}

/// Boton chico de accion sobre una sesion.
class BotonAccion extends StatelessWidget {
  const BotonAccion({super.key, required this.icono, required this.texto, required this.onTap, this.color});

  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tono = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: tono,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
      icon: Icon(icono, size: 16),
      label: Text(texto),
    );
  }
}

/// Hoja con la consulta completa (seleccionable) y un boton para copiarla.
Future<void> mostrarConsulta(BuildContext context, {required String titulo, String? subtitulo, required String? sql}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final texto = (sql ?? "").trim();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titulo, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          if (subtitulo != null) ...[
                            const SizedBox(height: 2),
                            Text(subtitulo, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                    if (texto.isNotEmpty)
                      IconButton(
                        tooltip: "Copiar consulta",
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: texto));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Consulta copiada.")));
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        texto.isEmpty ? "Sin consulta." : texto,
                        style: AppTextStyles.tech(
                          color: colorScheme.onSurface,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Pide confirmacion, ejecuta la accion y avisa como salio. Devuelve true si
/// se ejecuto bien.
Future<bool> confirmarAccion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String boton,
  required Future<void> Function() tarea,
  required String exito,
}) async {
  final mensajero = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancelar")),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: StatusColors.critico, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(boton),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await tarea();
    mensajero.showSnackBar(SnackBar(content: Text(exito), backgroundColor: StatusColors.exitoso));
    return true;
  } catch (e) {
    final texto = e is ComandoFallidoException ? e.mensaje : e.toString().replaceFirst("Exception: ", "");
    mensajero.showSnackBar(SnackBar(content: Text(texto), backgroundColor: StatusColors.critico));
    return false;
  }
}

/// Fila de indicadores (TOTAL / ACTIVAS / ...) arriba de cada vista.
class FilaIndicadores extends StatelessWidget {
  const FilaIndicadores(this.items, {super.key});

  /// (etiqueta, valor, color o null para neutro, icono)
  final List<(String, String, Color?, IconData)> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: IndicadorTile(etiqueta: items[i].$1, valor: items[i].$2, color: items[i].$3, icono: items[i].$4),
          ),
        ],
      ],
    );
  }
}

/// Aviso tocable (p.ej. «2 sesiones esperan: ver bloqueos»).
class AvisoTocable extends StatelessWidget {
  const AvisoTocable({super.key, required this.texto, required this.icono, required this.color, this.onTap, this.accion});

  final String texto;
  final IconData icono;
  final Color color;
  final VoidCallback? onTap;
  final String? accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(icono, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
                ),
              ),
              if (accion != null) ...[
                const SizedBox(width: 8),
                Text(accion!, style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_right_rounded, color: color, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
