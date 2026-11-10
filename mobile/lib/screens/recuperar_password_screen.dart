import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../services/auth_service.dart";
import "../services/notification_service.dart";
import "../theme.dart";
import "../widgets/fondo_app.dart";
import "../widgets/titulo_seccion.dart";
import "../widgets/version_app.dart";
import "dashboard_screen.dart";

/// «Olvidé mi contraseña»: en dos pasos y sin saber la anterior.
///  1. Usuario o correo -> el backend manda un código de 6 dígitos al correo
///     de la cuenta (sale por OP_PROD, dentro de la red).
///  2. Código + contraseña nueva -> se guarda y entra directo.
/// La contraseña nueva viaja solo a /auth/restablecer (HTTPS); en el
/// celular no se guarda, solo los tokens de sesión.
class RecuperarPasswordScreen extends StatefulWidget {
  final String? usuarioInicial;

  /// Texto arriba del formulario, p. ej. cuando la cuenta todavía no tiene
  /// contraseña para la app.
  final String? aviso;

  /// Para las pruebas; normalmente null.
  final AuthService? servicio;

  const RecuperarPasswordScreen({super.key, this.usuarioInicial, this.aviso, this.servicio});

  @override
  State<RecuperarPasswordScreen> createState() => _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen> {
  static const _esperaReenvio = 60;

  late final AuthService _auth = widget.servicio ?? AuthService();
  final _formUsuario = GlobalKey<FormState>();
  final _formCodigo = GlobalKey<FormState>();

  final _usuarioController = TextEditingController();
  final _codigoController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _codigoPedido = false;
  bool _cargando = false;
  bool _ocultarNueva = true;
  String? _error;
  String? _info;
  bool _infoDemora = false;
  int _segundosReenvio = 0;
  Timer? _timer;

  bool get _tieneLongitud => _nuevaController.text.length >= 8;
  bool get _tieneNumero => RegExp(r"\d").hasMatch(_nuevaController.text);
  bool get _tieneSimbolo => RegExp(r"[^A-Za-z0-9]").hasMatch(_nuevaController.text);

  @override
  void initState() {
    super.initState();
    _usuarioController.text = widget.usuarioInicial ?? "";
    _nuevaController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _usuarioController.dispose();
    _codigoController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  void _arrancarEspera() {
    _timer?.cancel();
    setState(() => _segundosReenvio = _esperaReenvio);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _segundosReenvio--);
      if (_segundosReenvio <= 0) t.cancel();
    });
  }

  Future<void> _pedirCodigo() async {
    if (!_codigoPedido && !(_formUsuario.currentState?.validate() ?? false)) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final respuesta = await _auth.solicitarRecuperacion(_usuarioController.text.trim());
      if (!mounted) return;
      setState(() {
        _codigoPedido = true;
        _info = respuesta.mensaje;
        _infoDemora = !respuesta.ok;
        _codigoController.clear();
      });
      _arrancarEspera();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiar() async {
    if (!(_formCodigo.currentState?.validate() ?? false)) return;
    if (!_tieneLongitud || !_tieneNumero || !_tieneSimbolo) {
      setState(() => _error = "La nueva contraseña no cumple los requisitos de seguridad.");
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await _auth.restablecerPassword(
        identificador: _usuarioController.text.trim(),
        codigo: _codigoController.text.trim(),
        passwordNueva: _nuevaController.text,
      );
      await NotificationService().inicializar();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cambiarUsuario() {
    _timer?.cancel();
    setState(() {
      _codigoPedido = false;
      _error = null;
      _info = null;
      _segundosReenvio = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: VersionApp(
                style: theme.textTheme.labelSmall?.copyWith(
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
                child: Vidrio(
                  radius: 24,
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: CajaIcono(
                          _codigoPedido ? Icons.mark_email_read_outlined : Icons.lock_reset_rounded,
                          tamano: 56,
                          tamanoIcono: 28,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _codigoPedido ? "Revisa tu correo" : "Recuperar contraseña",
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _codigoPedido
                            ? "Escribe el código de 6 dígitos que te llegó y elige tu contraseña nueva."
                            : "Te mandamos un código al correo de tu cuenta para que elijas una contraseña nueva. "
                                "No hace falta la anterior.",
                        style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      if (widget.aviso != null && !_codigoPedido) ...[
                        MensajeInline(widget.aviso!, color: colorScheme.primary, icono: Icons.info_outline),
                        const SizedBox(height: 16),
                      ],
                      if (_info != null && _codigoPedido) ...[
                        MensajeInline(
                          _info!,
                          color: _infoDemora ? StatusColors.advertencia : StatusColors.exitoso,
                          icono: _infoDemora ? Icons.schedule_send_outlined : Icons.forward_to_inbox_outlined,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_error != null) ...[
                        MensajeInline(_error!),
                        const SizedBox(height: 16),
                      ],
                      if (_codigoPedido) _pasoCodigo(theme) else _pasoUsuario(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pasoUsuario() {
    return Form(
      key: _formUsuario,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EtiquetaCampo("Usuario o correo"),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key("recuperar_usuario"),
            controller: _usuarioController,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.send,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v?.trim().isEmpty ?? true) ? "Escribe tu usuario o tu correo" : null,
            onFieldSubmitted: (_) => _pedirCodigo(),
          ),
          const SizedBox(height: 24),
          _BotonPrincipal(
            texto: "Enviar código",
            icono: Icons.send_rounded,
            cargando: _cargando,
            onPressed: _pedirCodigo,
          ),
        ],
      ),
    );
  }

  Widget _pasoCodigo(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Form(
      key: _formCodigo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _usuarioController.text.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: _cargando ? null : _cambiarUsuario,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text("Cambiar", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _EtiquetaCampo("Código del correo"),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key("recuperar_codigo"),
            controller: _codigoController,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 10),
            decoration: const InputDecoration(hintText: "······"),
            validator: (v) => (v ?? "").trim().length == 6 ? null : "El código tiene 6 dígitos",
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _cargando || _segundosReenvio > 0 ? null : _pedirCodigo,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _segundosReenvio > 0 ? "Reenviar en $_segundosReenvio s" : "¿No llegó? Reenviar código",
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 14),
          const _EtiquetaCampo("Nueva contraseña"),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key("recuperar_nueva"),
            controller: _nuevaController,
            obscureText: _ocultarNueva,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.lock_reset, color: colorScheme.primary),
              suffixIcon: IconButton(
                icon: Icon(_ocultarNueva ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _ocultarNueva = !_ocultarNueva),
              ),
            ),
            validator: (v) => (v ?? "").length < 8 ? "Mínimo 8 caracteres" : null,
          ),
          const SizedBox(height: 16),
          const _EtiquetaCampo("Confirmar nueva contraseña"),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key("recuperar_confirmar"),
            controller: _confirmarController,
            obscureText: _ocultarNueva,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.lock_outline)),
            validator: (v) => v != _nuevaController.text ? "Las contraseñas no coinciden" : null,
          ),
          const SizedBox(height: 16),
          Container(
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
                _Requisito(cumplido: _tieneLongitud, texto: "Mínimo 8 caracteres"),
                _Requisito(cumplido: _tieneNumero, texto: "Incluir un número"),
                _Requisito(cumplido: _tieneSimbolo, texto: "Incluir un símbolo"),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _BotonPrincipal(
            texto: "Cambiar y entrar",
            icono: Icons.arrow_forward,
            cargando: _cargando,
            onPressed: _cambiar,
          ),
        ],
      ),
    );
  }
}

class _BotonPrincipal extends StatelessWidget {
  final String texto;
  final IconData icono;
  final bool cargando;
  final VoidCallback onPressed;

  const _BotonPrincipal({required this.texto, required this.icono, required this.cargando, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: cargando ? null : onPressed,
        child: cargando
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Text(texto), const SizedBox(width: 8), Icon(icono, size: 18)],
              ),
      ),
    );
  }
}

class _EtiquetaCampo extends StatelessWidget {
  final String texto;

  const _EtiquetaCampo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(left: 4), child: Eyebrow(texto));
  }
}

class _Requisito extends StatelessWidget {
  final bool cumplido;
  final String texto;

  const _Requisito({required this.cumplido, required this.texto});

  @override
  Widget build(BuildContext context) {
    final color = cumplido ? StatusColors.exitoso : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(cumplido ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 18, color: color),
          const SizedBox(width: 8),
          Text(texto, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
