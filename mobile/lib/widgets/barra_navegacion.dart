import "dart:ui";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

/// Barra inferior flotante: una pastilla de vidrio separada de los bordes,
/// con la pestana activa resaltada en lima. Reemplaza al NavigationBar
/// estandar (franja pegada al borde) para que la pantalla se vea de una
/// pieza con las tarjetas translucidas.
class BarraNavegacion extends StatelessWidget {
  const BarraNavegacion({
    super.key,
    required this.indice,
    required this.destinos,
    required this.onSeleccionar,
  });

  final int indice;
  final List<DestinoNavegacion> destinos;
  final ValueChanged<int> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 68,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var i = 0; i < destinos.length; i++)
                  Expanded(
                    child: _Destino(
                      destino: destinos[i],
                      activo: i == indice,
                      onTap: () {
                        if (i != indice) HapticFeedback.selectionClick();
                        onSeleccionar(i);
                      },
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

class DestinoNavegacion {
  const DestinoNavegacion({required this.icono, required this.iconoActivo, required this.etiqueta});

  final IconData icono;
  final IconData iconoActivo;
  final String etiqueta;
}

class _Destino extends StatelessWidget {
  const _Destino({required this.destino, required this.activo, required this.onTap});

  final DestinoNavegacion destino;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colorTexto = activo ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: activo,
      label: destino.etiqueta,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: activo ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(activo ? destino.iconoActivo : destino.icono, size: 22, color: colorTexto),
                const SizedBox(height: 3),
                Text(
                  destino.etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorTexto,
                    letterSpacing: 0.1,
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
