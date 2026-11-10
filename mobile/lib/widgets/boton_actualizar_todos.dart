import "package:flutter/material.dart";

import "titulo_seccion.dart";

/// «Actualizar todos» del encabezado de Procesos/Tablas (solo administradores).
/// Una píldora con el tono de acento. Mientras OP_PROD trabaja, el icono gira,
/// el botón no se puede tocar y, si se conoce el avance, se llena de izquierda
/// a derecha y dice «3/12».
class BotonActualizarTodos extends StatefulWidget {
  const BotonActualizarTodos({
    super.key,
    required this.onPressed,
    this.ocupado = false,
    this.completados,
    this.total,
  });

  final VoidCallback? onPressed;
  final bool ocupado;
  final int? completados;
  final int? total;

  @override
  State<BotonActualizarTodos> createState() => _BotonActualizarTodosState();
}

class _BotonActualizarTodosState extends State<BotonActualizarTodos> with SingleTickerProviderStateMixin {
  late final AnimationController _giro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.ocupado) _giro.repeat();
  }

  @override
  void didUpdateWidget(BotonActualizarTodos anterior) {
    super.didUpdateWidget(anterior);
    if (widget.ocupado && !_giro.isAnimating) {
      _giro.repeat();
    } else if (!widget.ocupado && _giro.isAnimating) {
      // Termina la vuelta en curso en vez de quedar torcido.
      _giro.animateTo(1).then((_) {
        if (mounted && !widget.ocupado) _giro.value = 0;
      });
    }
  }

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  double? get _avance {
    final total = widget.total ?? 0;
    if (!widget.ocupado || total <= 0) return null;
    return ((widget.completados ?? 0) / total).clamp(0.0, 1.0);
  }

  String get _texto {
    if (!widget.ocupado) return "Actualizar todos";
    final total = widget.total ?? 0;
    return total > 0 ? "Actualizando ${widget.completados ?? 0}/$total" : "Actualizando…";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tinta = acentoTinta(context);
    final avance = _avance;
    final habilitado = !widget.ocupado && widget.onPressed != null;

    return Semantics(
      button: true,
      enabled: habilitado,
      label: widget.ocupado ? _texto : "Actualizar todos: relanza los que están en error o demorados",
      excludeSemantics: true,
      child: Material(
        color: tinta.withValues(alpha: widget.ocupado ? 0.08 : 0.14),
        shape: StadiumBorder(side: BorderSide(color: tinta.withValues(alpha: 0.38))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: habilitado ? widget.onPressed : null,
          child: Stack(
            children: [
              if (avance != null)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: avance),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (context, valor, _) => FractionallySizedBox(
                        widthFactor: valor,
                        heightFactor: 1,
                        child: ColoredBox(color: tinta.withValues(alpha: 0.22)),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 13, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RotationTransition(
                      turns: _giro,
                      child: Icon(Icons.sync_rounded, size: 16, color: tinta),
                    ),
                    const SizedBox(width: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        _texto,
                        key: ValueKey(_texto),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tinta,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: 0.1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
