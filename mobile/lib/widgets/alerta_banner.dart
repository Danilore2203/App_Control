import "package:flutter/material.dart";

import "../theme.dart";

/// Banner rojo en la parte superior cuando hay procesos en estado critico
/// (color rojo). Se puede cerrar; vuelve a aparecer si se recarga la lista.
class AlertaBanner extends StatefulWidget {
  final int cantidadCriticos;
  final List<String> fuentesAfectadas;
  final VoidCallback? onTap;

  const AlertaBanner({
    super.key,
    required this.cantidadCriticos,
    required this.fuentesAfectadas,
    this.onTap,
  });

  @override
  State<AlertaBanner> createState() => _AlertaBannerState();
}

class _AlertaBannerState extends State<AlertaBanner> {
  bool _cerrado = false;

  @override
  void didUpdateWidget(covariant AlertaBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cantidadCriticos != widget.cantidadCriticos) {
      _cerrado = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cerrado || widget.cantidadCriticos == 0)
      return const SizedBox.shrink();

    final texto = widget.fuentesAfectadas.isEmpty
        ? "${widget.cantidadCriticos} proceso(s) en estado crítico"
        : "${widget.cantidadCriticos} proceso(s) en estado crítico en ${widget.fuentesAfectadas.join(", ")}";

    return Material(
      color: Color.lerp(StatusColors.critico, Colors.black, 0.35)!,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: () => setState(() => _cerrado = true),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
