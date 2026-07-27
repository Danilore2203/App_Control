import "package:flutter/material.dart";

/// Fondo con una textura sutil de puntos, como en los paneles de referencia.
/// Envuelve cualquier contenido (child) sobre un color/gradiente de base.
class DottedBackground extends StatelessWidget {
  final Widget child;
  final Color dotColor;
  final double spacing;

  const DottedBackground({
    super.key,
    required this.child,
    required this.dotColor,
    this.spacing = 22,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotGridPainter(dotColor: dotColor, spacing: spacing),
      child: child,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color dotColor;
  final double spacing;

  _DotGridPainter({required this.dotColor, required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.dotColor != dotColor || oldDelegate.spacing != spacing;
}
