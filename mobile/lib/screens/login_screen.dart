import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter/services.dart" show TextInput;

import "../services/auth_service.dart";
import "../services/biometric_service.dart";
import "../services/notification_service.dart";
import "../widgets/fondo_app.dart";
import "../widgets/titulo_seccion.dart";
import "../widgets/version_app.dart";
import "dashboard_screen.dart";
import "recuperar_password_screen.dart";
import "register_screen.dart";

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

    if (!_hayTokenGuardado) return;

    // Si el proceso de la app se reinicio de cero (la cerraste del todo:
    // swipe desde recientes, o Android la mato) SIEMPRE hay que pedir
    // huella, sin importar la ventana de gracia configurada en Ajustes -
    // por eso ni se llama a ingresoRecienteVigente() en ese caso. Esa
    // ventana solo tiene sentido si el proceso seguia vivo (la app nunca
    // se cerro del todo, solo paso a segundo plano un momento).
    final esArranqueNuevo = _biometricService.esArranqueNuevoDelProceso;
    if (!esArranqueNuevo && await _biometricService.ingresoRecienteVigente()) {
      await _entrarADashboard();
      return;
    }

    if (_biometriaDisponible) {
      _desbloquearConBiometria();
    }
  }

  Future<void> _entrarADashboard() async {
    await _biometricService.registrarIngresoExitoso();
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

    if (!ok) {
      setState(() {
        _cargando = false;
        _error = "No se pudo verificar tu identidad.";
      });
      return;
    }

    // La huella solo confirma que sos vos - no confirma que la sesion siga
    // viva en el backend. Se intenta refrescar antes de entrar: si el
    // refresh_token tambien esta vencido, se manda al formulario de login
    // en vez de entrar con una sesion muerta (antes pasaba justo eso: entraba
    // igual y recien ahi el usuario empezaba a ver errores en cada pantalla).
    try {
      await _authService.refrescarToken();
    } on SesionExpiradaException {
      if (!mounted) return;
      await _authService.logout();
      setState(() {
        _cargando = false;
        _hayTokenGuardado = false;
        _error = "Tu sesión expiró. Iniciá sesión de nuevo.";
      });
      return;
    } catch (_) {
      // Error de red/timeout al refrescar: no bloquea el ingreso, el resto
      // de la app ya maneja sus propios errores de conexion pantalla por
      // pantalla.
    }

    await _entrarADashboard();
  }

  Future<void> _iniciarSesion() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      await _authService.login(_usuarioController.text.trim(), _passwordController.text);
      // Login correcto: el sistema ofrece guardar usuario y contraseña en su gestor.
      TextInput.finishAutofillContext();
      await _entrarADashboard();
    } on RequiereConfigurarPasswordException catch (_) {
      if (!mounted) return;
      _irARecuperarPassword(
        aviso: "Tu cuenta todavía no tiene contraseña para la app. Te mandamos un código al correo para crearla.",
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

  void _irARecuperarPassword({String? aviso}) {
    final usuario = _usuarioController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecuperarPasswordScreen(usuarioInicial: usuario.isEmpty ? null : usuario, aviso: aviso),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SizedBox.expand(
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
                            Vidrio(
                              radius: 24,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _hayTokenGuardado ? "Bienvenido de nuevo" : "Bienvenido",
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.6,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _hayTokenGuardado
                                          ? "Confirmá tu identidad para continuar"
                                          : "Ingresá para acceder al monitor",
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 24),
                                    if (_error != null) ...[
                                      MensajeInline(_error!),
                                      const SizedBox(height: 18),
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
                                      // AutofillGroup + hints: el gestor de contraseñas del
                                      // celular (Llavero en iPhone/Safari, Google en Android)
                                      // ofrece guardarla y completarla. La app no la guarda.
                                      AutofillGroup(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            const _EtiquetaCampo(texto: "Usuario o email"),
                                            const SizedBox(height: 6),
                                            TextField(
                                              key: const Key("login_usuario"),
                                              controller: _usuarioController,
                                              autofillHints: const [AutofillHints.username],
                                              autocorrect: false,
                                              enableSuggestions: false,
                                              textInputAction: TextInputAction.next,
                                              decoration: const InputDecoration(
                                                hintText: "nombre.apellido@nuevatel.com",
                                                prefixIcon: Icon(Icons.alternate_email),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            const _EtiquetaCampo(texto: "Contraseña"),
                                            const SizedBox(height: 6),
                                            TextField(
                                              key: const Key("login_password"),
                                              controller: _passwordController,
                                              obscureText: _ocultarPassword,
                                              autofillHints: const [AutofillHints.password],
                                              textInputAction: TextInputAction.done,
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
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _irARecuperarPassword,
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
                                      // En la version web (Safari en iPhone) Google no esta
                                      // autorizado para ese dominio: solo usuario y contraseña.
                                      if (!kIsWeb) ...[
                                        const SizedBox(height: 8),
                                        const _Separador(texto: "o ingresá con"),
                                        const SizedBox(height: 16),
                                        _BotonAncho(onTap: _iniciarSesionConGoogle),
                                      ],
                                    ],
                                  ],
                                ),
                            ),
                            const SizedBox(height: 24),
                            VersionApp(
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colorScheme.outline,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: colorScheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Eyebrow(texto),
        ),
        Expanded(child: Divider(color: colorScheme.outlineVariant)),
      ],
    );
  }
}

class _Encabezado extends StatelessWidget {
  final ColorScheme colorScheme;

  const _Encabezado({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: colorScheme.primary.withValues(alpha: 0.4), blurRadius: 28, offset: const Offset(0, 8)),
            ],
          ),
          child: Icon(Icons.insights_rounded, size: 34, color: colorScheme.onPrimary),
        ),
        const SizedBox(height: 16),
        Text(
          "Controles",
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        ),
        const SizedBox(height: 2),
        const Eyebrow("Monitoreo y alertas · Centinela DWH"),
      ],
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
    final colorScheme = Theme.of(context).colorScheme;
    final esGoogle = icono == null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: esGoogle
          ? OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                backgroundColor: colorScheme.surfaceContainerHighest,
                foregroundColor: colorScheme.onSurface,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleLogo(),
                  const SizedBox(width: 12),
                  Text(texto, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icono, size: 20),
              label: Text(texto),
            ),
    );
  }
}

class _BotonHuella extends StatelessWidget {
  final VoidCallback onTap;

  const _BotonHuella({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Separador(texto: "ingresá con tu huella"),
        const SizedBox(height: 18),
        _IconoSecundario(icono: Icons.fingerprint_rounded, onTap: onTap),
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
      child: Material(
        color: colorScheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: colorScheme.primary.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: -2),
              ],
            ),
            child: Icon(icono, size: 36, color: colorScheme.onPrimary),
          ),
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
