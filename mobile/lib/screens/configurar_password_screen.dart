import "package:flutter/material.dart";

import "../services/auth_service.dart";
import "../services/notification_service.dart";
import "../theme.dart";
import "../widgets/fondo_app.dart";
import "../widgets/titulo_seccion.dart";
import "../widgets/version_app.dart";
import "dashboard_screen.dart";

/// Para cuentas (tipicamente AD) que todavia no tienen una contraseña local
/// configurada, o quieren cambiarla. Se valida la contraseña actual (contra
/// AD/monitor, o contra la local si ya existia) antes de guardar la nueva.
class ConfigurarPasswordScreen extends StatefulWidget {
  final String? usuarioInicial;
  final bool esPrimeraVez;

  const ConfigurarPasswordScreen({
    super.key,
    this.usuarioInicial,
    this.esPrimeraVez = false,
  });

  @override
  State<ConfigurarPasswordScreen> createState() => _ConfigurarPasswordScreenState();
}

class _ConfigurarPasswordScreenState extends State<ConfigurarPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _usuarioController = TextEditingController();
  final _actualController = TextEditingController();
  final _correoController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _cargando = false;
  String? _error;
  bool _ocultarActual = true;
  bool _ocultarNueva = true;

  bool get _tieneLongitud => _nuevaController.text.length >= 8;
  bool get _tieneNumero => RegExp(r"\d").hasMatch(_nuevaController.text);
  bool get _tieneSimbolo => RegExp(r"[^A-Za-z0-9]").hasMatch(_nuevaController.text);

  @override
  void initState() {
    super.initState();
    _nuevaController.addListener(() => setState(() {}));
    if (widget.usuarioInicial != null) {
      _usuarioController.text = widget.usuarioInicial!;
    }
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _actualController.dispose();
    _correoController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_tieneLongitud || !_tieneNumero || !_tieneSimbolo) {
      setState(() => _error = "La nueva contraseña no cumple los requisitos de seguridad.");
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      await _authService.configurarPassword(
        username: _usuarioController.text.trim(),
        passwordActual: widget.esPrimeraVez ? null : _actualController.text,
        correoVerificacion: widget.esPrimeraVez ? _correoController.text.trim() : null,
        passwordNueva: _nuevaController.text,
      );
      await NotificationService().inicializar();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: VersionApp(
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SizedBox.expand(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Vidrio(
                      radius: 24,
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: CajaIcono(
                            widget.esPrimeraVez ? Icons.waving_hand_rounded : Icons.lock_reset_rounded,
                            tamano: 56,
                            tamanoIcono: 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.esPrimeraVez ? "¡Bienvenido!" : "Cambio de contraseña",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.esPrimeraVez
                              ? "Tu cuenta es valida pero todavia no tiene contraseña para esta "
                                  "app. Confirma tu correo de Nuevatel y registra una para continuar."
                              : "Confirma tu usuario y contraseña habituales, y elige una "
                                  "contraseña nueva para esta app.",
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[
                          MensajeInline(_error!),
                          const SizedBox(height: 18),
                        ],
                        const _EtiquetaCampo(texto: "Usuario"),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _usuarioController,
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
                          validator: (valor) =>
                              (valor?.trim().isEmpty ?? true) ? "El usuario es obligatorio" : null,
                        ),
                        const SizedBox(height: 16),
                        if (widget.esPrimeraVez) ...[
                          const _EtiquetaCampo(texto: "Correo Nuevatel"),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _correoController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              hintText: "nombre.apellido@nuevatel.com",
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                            validator: (valor) {
                              final texto = valor?.trim().toLowerCase() ?? "";
                              if (texto.isEmpty) return "Ingresa tu correo de Nuevatel";
                              if (!texto.endsWith("@nuevatel.com")) {
                                return "Debe ser un correo @nuevatel.com";
                              }
                              return null;
                            },
                          ),
                        ] else ...[
                          const _EtiquetaCampo(texto: "Contraseña actual"),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _actualController,
                            obscureText: _ocultarActual,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_ocultarActual ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _ocultarActual = !_ocultarActual),
                              ),
                            ),
                            validator: (valor) =>
                                (valor?.isEmpty ?? true) ? "Ingresa tu contraseña actual" : null,
                          ),
                        ],
                        const SizedBox(height: 20),
                        Divider(color: colorScheme.outlineVariant),
                        const SizedBox(height: 20),
                        const _EtiquetaCampo(texto: "Nueva contraseña"),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nuevaController,
                          obscureText: _ocultarNueva,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.lock_reset, color: colorScheme.primary),
                            suffixIcon: IconButton(
                              icon: Icon(_ocultarNueva ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _ocultarNueva = !_ocultarNueva),
                            ),
                          ),
                          validator: (valor) {
                            if ((valor ?? "").length < 8) return "Mínimo 8 caracteres";
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        const _EtiquetaCampo(texto: "Confirmar nueva contraseña"),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _confirmarController,
                          obscureText: _ocultarNueva,
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline)),
                          validator: (valor) {
                            if (valor != _nuevaController.text) return "Las contraseñas no coinciden";
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Eyebrow("Requisitos de seguridad"),
                              const SizedBox(height: 8),
                              _RequisitoItem(cumplido: _tieneLongitud, texto: "Mínimo 8 caracteres"),
                              _RequisitoItem(cumplido: _tieneNumero, texto: "Incluir un número"),
                              _RequisitoItem(cumplido: _tieneSimbolo, texto: "Incluir un símbolo"),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _cargando ? null : _guardar,
                            child: _cargando
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(widget.esPrimeraVez ? "Registrar y entrar" : "Actualizar y entrar"),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward, size: 18),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _InsigniaPie(icono: Icons.lock_outline_rounded, texto: "Conexión segura"),
                            SizedBox(width: 16),
                            _InsigniaPie(icono: Icons.enhanced_encryption_outlined, texto: "Datos cifrados"),
                          ],
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ),
    );
  }
}

class _EtiquetaCampo extends StatelessWidget {
  final String texto;

  const _EtiquetaCampo({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Eyebrow(texto),
      ),
    );
  }
}

class _InsigniaPie extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _InsigniaPie({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 13, color: color),
        const SizedBox(width: 4),
        Text(texto, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _RequisitoItem extends StatelessWidget {
  final bool cumplido;
  final String texto;

  const _RequisitoItem({required this.cumplido, required this.texto});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = cumplido ? StatusColors.exitoso : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            cumplido ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(texto, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
