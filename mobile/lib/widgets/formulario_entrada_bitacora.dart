import "package:flutter/material.dart";

import "../models/bitacora_error.dart";
import "../services/api_service.dart";
import "../utils/meses_es.dart";

/// Formulario de carga manual de bitácora, compartido entre la vista de mes
/// (sin fecha fija, usa la hora del servidor) y la vista de día (fecha fija
/// al día que se está viendo). Antes existían dos copias casi idénticas en
/// bitacora_mes_screen.dart y bitacora_dia_screen.dart.
class FormularioEntradaBitacora extends StatefulWidget {
  final DateTime? fechaHora;

  const FormularioEntradaBitacora({super.key, this.fechaHora});

  @override
  State<FormularioEntradaBitacora> createState() =>
      _FormularioEntradaBitacoraState();
}

class _FormularioEntradaBitacoraState
    extends State<FormularioEntradaBitacora> {
  final _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  bool _esProceso = true;
  String _tecnologia = tecnologiasProceso.first;
  String _estado = estadosProceso.first;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _apiService.crearEntradaBitacora(
        nombre: _nombreController.text.trim(),
        tecnologia: _tecnologia,
        estado: _estado,
        descripcion: _descripcionController.text.trim(),
        fechaHora: widget.fechaHora,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final opciones = _esProceso ? tecnologiasProceso : tecnologiasTabla;
    final opcionesEstado = _esProceso ? estadosProceso : estadosTabla;
    final fecha = widget.fechaHora;
    final titulo = fecha == null
        ? "Registrar evento"
        : "Registrar evento · ${fecha.day} DE ${nombresMesEs[fecha.month - 1].toUpperCase()}";

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(titulo, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text("Proceso")),
                  ButtonSegment(value: false, label: Text("Tabla")),
                ],
                selected: {_esProceso},
                onSelectionChanged: (seleccion) => setState(() {
                  _esProceso = seleccion.first;
                  _tecnologia = opciones.first;
                  _estado = (_esProceso ? estadosProceso : estadosTabla).first;
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _tecnologia,
                decoration: const InputDecoration(labelText: "Tecnología"),
                items: opciones
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (valor) => setState(() => _tecnologia = valor!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _estado,
                decoration: const InputDecoration(labelText: "Estado"),
                items: opcionesEstado
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (valor) => setState(() => _estado = valor!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombreController,
                decoration: InputDecoration(
                    labelText: _esProceso
                        ? "Nombre del proceso"
                        : "Nombre de la tabla"),
                validator: (valor) =>
                    (valor?.trim().isEmpty ?? true) ? "Obligatorio" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: "Descripción",
                  hintText: _esProceso
                      ? "Por qué falló el proceso..."
                      : "¿Tabla vacía? ¿Cuenta con datos incorrectos?...",
                ),
                validator: (valor) =>
                    (valor?.trim().isEmpty ?? true) ? "Obligatorio" : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: TextStyle(color: colorScheme.error, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Guardar"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
