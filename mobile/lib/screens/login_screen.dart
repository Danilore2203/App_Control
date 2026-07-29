import "package:flutter/material.dart";

import "../services/auth_service.dart";
import "../services/biometric_service.dart";
import "../services/notification_service.dart";
import "../theme.dart";
import "../widgets/dotted_background.dart";
import "configurar_password_screen.dart";
import "dashboard_screen.dart";
import "register_screen.dart";

const String _version = "v0.1.0";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _biometricService = BiometricService();

  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _ocultarPassword = true;

  bool _verificandoSesion = true;
  bool _hayTokenGuardado = false;
  bool _biometriaDisponible = false;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepararPantalla();
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _prepararPantalla() async {
    final token = await _authService.obtenerToken();
    final biometriaOk = await _biometricService.disponible();

    if (!mounted) return;
    setState(() {
      _hayTokenGuardado = token != null;
      _biometriaDisponible = biometriaOk;
      _verificandoSesion = false;
    });

    if (_hayTokenGuardado && _biometriaDisponible) {
      _desbloquearConBiometria();
    }
  }

  Future<void> _entrarADashboard() async {
    await NotificationService().inicializar();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  Future<void> _desbloquearConBiometria() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final ok = await _biometricService.autenticar();
    if (!mounted) return;

    if (ok) {
      await _entrarADashboard();
      return;
    }
    setState(() {
      _cargando = false;
      _error = "No se pudo verificar tu identidad.";
    });
  }

  Future<void> _iniciarSesion() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      await _authService.login(_usuarioController.text.trim(), _passwordController.text);
      await _entrarADashboard();
    } on RequiereConfigurarPasswordException catch (_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConfigurarPasswordScreen(
            usuarioInicial: _usuarioController.text.trim(),
            esPrimeraVez: true,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _iniciarSesionConGoogle() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      await _authService.loginConGoogle();
      await _entrarADashboard();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _usarOtraCuenta() async {
    await _authService.logout();
    if (!mounted) return;
    setState(() {
      _hayTokenGuardado = false;
      _error = null;
    });
  }

  void _irACrearCuenta() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  void _irAConfigurarPassword() {
    final usuario = _usuarioController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConfigurarPasswordScreen(usuarioInicial: usuario.isEmpty ? null : usuario),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: DottedBackground(
        dotColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.15),
        child: SizedBox.expand(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _verificandoSesion
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Encabezado(colorScheme: colorScheme),
                            const SizedBox(height: 28),
                            Card(
                              elevation: 8,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _hayTokenGuardado ? "Bienvenido de nuevo" : "Bienvenido",
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _hayTokenGuardado
                                          ? "Confirma tu identidad para continuar"
                                          : "Inicia sesión para acceder al panel de control",
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 28),
                                    if (_error != null) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: colorScheme.errorContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.error_outline,
                                                color: colorScheme.onErrorContainer, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _error!,
                                                style: TextStyle(
                                                    color: colorScheme.onErrorContainer, fontSize: 13),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                    ],
                                    if (_cargando)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 8),
                                        child: CircularProgressIndicator(),
                                      )
                                    else if (_hayTokenGuardado) ...[
                                      if (_biometriaDisponible)
                                        _BotonHuella(onTap: _desbloquearConBiometria)
                                      else
                                        _BotonAncho(
                                          onTap: _entrarADashboard,
                                          texto: "Continuar",
                                          icono: Icons.arrow_forward,
                                        ),
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: _usarOtraCuenta,
                                        child: const Text("Usar otra cuenta"),
                                      ),
                                    ] else ...[
                                      _EtiquetaCampo(texto: "USUARIO / EMAIL", colorScheme: colorScheme),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: _usuarioController,
                                        decoration: const InputDecoration(
                                          hintText: "nombre.apellido@nuevatel.com",
                                          prefixIcon: Icon(Icons.alternate_email),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      _EtiquetaCampo(texto: "CONTRASEÑA", colorScheme: colorScheme),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: _passwordController,
                                        obscureText: _ocultarPassword,
                                        decoration: InputDecoration(
                                          hintText: "••••••••",
                                          prefixIcon: const Icon(Icons.lock_outline),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _ocultarPassword ? Icons.visibility_off : Icons.visibility,
                                            ),
                                            onPressed: () =>
                                                setState(() => _ocultarPassword = !_ocultarPassword),
                                          ),
                                        ),
                                        onSubmitted: (_) => _iniciarSesion(),
                                      ),
                                      const SizedBox(height: 4),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _irAConfigurarPassword,
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(0, 32),
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: const Text(
                                            "Olvidé mi contraseña",
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 52,
                                        child: ElevatedButton(
                                          onPressed: _iniciarSesion,
                                          child: const Text("Ingresar"),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: _irACrearCuenta,
                                        child: const Text("¿No tienes cuenta? Crear cuenta"),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "O INGRESE CON",
                                        textAlign: TextAlign.center,
                                        style: AppTextStyles.tech(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      _BotonAncho(onTap: _iniciarSesionConGoogle),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _version.toUpperCase(),
                              style: AppTextStyles.tech(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                fontSize: 10,
                              ),
                            ),
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
}

class _Encabezado extends StatelessWidget {
  final ColorScheme colorScheme;

  const _Encabezado({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.insights, size: 30, color: colorScheme.onPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          "CONTROLES",
          style: AppTextStyles.tech(color: colorScheme.primary, fontSize: 20, letterSpacing: 1.5),
        ),
        Text(
          "MONITOREO Y ALERTAS",
          style: AppTextStyles.tech(
            color: colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _EtiquetaCampo extends StatelessWidget {
  final String texto;
  final ColorScheme colorScheme;

  const _EtiquetaCampo({required this.texto, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(texto, style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 10)),
    );
  }
}

/// Boton "Iniciar sesion con Google" (por defecto) o generico reutilizable
/// con el mismo look, para el caso "Continuar" cuando no hay biometria.
class _BotonAncho extends StatelessWidget {
  final VoidCallback onTap;
  final String texto;
  final IconData? icono;

  const _BotonAncho({
    required this.onTap,
    this.texto = "Iniciar sesión con Google",
    this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icono != null ? Icon(icono, size: 20, color: Colors.grey.shade800) : const _GoogleLogo(),
            const SizedBox(width: 12),
            Text(
              texto,
              style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonHuella extends StatelessWidget {
  final VoidCallback onTap;

  const _BotonHuella({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Text(
          "O INGRESA CON",
          style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 10),
        ),
        const SizedBox(height: 16),
        _IconoSecundario(icono: Icons.fingerprint, onTap: onTap),
      ],
    );
  }
}

class _IconoSecundario extends StatelessWidget {
  final IconData icono;
  final VoidCallback? onTap;

  const _IconoSecundario({required this.icono, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
          ),
          child: Icon(icono, size: 32, color: colorScheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

/// Aproximacion simple del logo de Google (4 colores) sin depender de un asset.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final strokeWidth = radius * 0.55;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(radius: radius - strokeWidth / 2, center: center);

    canvas.drawArc(rect, -1.55, 1.6, false, paint..color = const Color(0xFF4285F4));
    canvas.drawArc(rect, 0.05, 1.5, false, paint..color = const Color(0xFF34A853));
    canvas.drawArc(rect, 1.55, 1.5, false, paint..color = const Color(0xFFFBBC05));
    canvas.drawArc(rect, 3.05, 1.5, false, paint..color = const Color(0xFFEA4335));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
