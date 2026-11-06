import "dart:ui";

import "package:flutter/material.dart";

import "../theme.dart";
import "dotted_background.dart";

/// Fondo de toda la app, como la pagina del monitor web de OP: color de
/// pagina, un brillo lima difuso arriba a la izquierda y una trama sutil de
/// puntos. Las tarjetas translucidas (surfaceContainerHigh) se ven "vidrio"
/// justamente porque dejan pasar este fondo. Se instala una sola vez desde
/// MaterialApp.builder, asi todas las pantallas lo comparten.
class FondoApp extends StatelessWidget {
  const FondoApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pagina = isDark ? OpTokens.pageDark : OpTokens.pageLight;
    final acento = isDark ? OpTokens.accentDark : OpTokens.accentLight;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF181C19), pagina, const Color(0xFF121412)]
                  : [const Color(0xFFF3F6EE), pagina, const Color(0xFFE9ECF0)],
            ),
          ),
        ),
        // Brillo lima difuso (radial-gradient de .lt-hs-card / .bt-kpi-card).
        Positioned(
          top: -140,
          left: -120,
          child: Container(
            width: 420,
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [acento.withValues(alpha: isDark ? 0.22 : 0.30), acento.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -200,
          right: -160,
          child: Container(
            width: 460,
            height: 460,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [acento.withValues(alpha: isDark ? 0.10 : 0.14), acento.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        DottedBackground(
          dotColor: (isDark ? Colors.white : OpTokens.textLight).withValues(alpha: isDark ? 0.05 : 0.07),
          spacing: 24,
          child: child,
        ),
      ],
    );
  }
}

/// Panel "vidrio": fondo translucido con desenfoque de lo que hay detras,
/// borde fino y radio 16 (el .pm-panel con --pm-glass-blur de la web). Para
/// tarjetas destacadas (indicadores, cabeceras); las listas largas usan el
/// color translucido sin desenfoque, que es mas barato de pintar.
class Vidrio extends StatelessWidget {
  const Vidrio({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = OpTokens.radius,
    this.color,
    this.borderColor,
    this.blur = 14,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final double blur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borde = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: borde,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: color ?? colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: borde,
            side: BorderSide(color: borderColor ?? colorScheme.outlineVariant),
          ),
          child: InkWell(
            borderRadius: borde,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
