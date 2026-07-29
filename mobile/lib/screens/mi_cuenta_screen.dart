import "dart:ui";

import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "../models/usuario.dart";
import "../services/api_service.dart";
import "../services/auth_service.dart";
import "../theme.dart";
import "configurar_password_screen.dart";

/// Perfil del usuario: datos basicos de la cuenta AD y vinculacion opcional
/// con una cuenta de Google (self-service, sin pasar por aprobacion de admin)
/// para poder entrar mas rapido la proxima vez.
class MiCuentaScreen extends StatefulWidget {
  const MiCuentaScreen({super.key});

  @override
  State<MiCuentaScreen> createState() => _MiCuentaScreenState();
}

class _MiCuentaScreenState extends State<MiCuentaScreen> {
  final _authService = AuthService();
  final _apiService = ApiService();

  Usuario? _usuario;
  bool _cargandoPerfil = true;
  bool _cargandoAccion = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    try {
      final usuario = await _apiService.obtenerPerfil();
      if (!mounted) return;
      setState(() {
        _usuario = usuario;
        _cargandoPerfil = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst("Exception: ", "");
        _cargandoPerfil = false;
      });
    }
  }

  Future<void> _vincularGoogle() async {
    setState(() {
      _cargandoAccion = true;
      _error = null;
    });
    try {
      final usuario = await _authService.vincularGoogle();
      if (!mounted) return;
      setState(() => _usuario = usuario);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cargandoAccion = false);
    }
  }

  Future<void> _desvincularGoogle() async {
    setState(() {
      _cargandoAccion = true;
      _error = null;
    });
    try {
      final usuario = await _authService.desvincularGoogle();
      if (!mounted) return;
      setState(() => _usuario = usuario);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _cargandoAccion = false);
    }
  }

  void _irAActualizarClave() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConfigurarPasswordScreen()),
    );
  }

  void _mostrarLogProximamente() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Log de accesos: todavía no disponible.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final usuario = _usuario;
    final tieneGoogle = usuario?.emailGoogle != null;
    final inicial = (usuario?.nombre?.trim().isNotEmpty ?? false)
        ? usuario!.nombre!.trim()[0].toUpperCase()
        : (usuario?.username.isNotEmpty ?? false)
            ? usuario!.username[0].toUpperCase()
            : "?";

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text("Mi cuenta"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _AvatarChico(inicial: inicial, colorScheme: colorScheme),
          ),
        ],
      ),
      body: _cargandoPerfil
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: colorScheme.onErrorContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (usuario != null) ...[
                    _TarjetaResumen(
                      inicial: inicial,
                      nombre: usuario.nombre ?? usuario.username,
                      rol: usuario.esAdmin ? "ADMINISTRADOR" : "MONITOREO Y ALERTAS",
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 24),
                    _TituloSeccion(texto: "CUENTA AD", colorScheme: colorScheme),
                    const SizedBox(height: 8),
                    _GlassCard(
                      colorScheme: colorScheme,
                      bordeIzquierdo: colorScheme.primary,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _IconoCaja(icono: Icons.apartment, colorScheme: colorScheme),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  usuario.nombre ?? usuario.username,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  usuario.email ?? usuario.username,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: colorScheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _PuntoPulsante(color: colorScheme.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Sincronizado con Active Directory",
                                      style: AppTextStyles.tech(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _TituloSeccion(texto: "CUENTA DE GOOGLE VINCULADA", colorScheme: colorScheme),
                    const SizedBox(height: 8),
                    _GlassCard(
                      colorScheme: colorScheme,
                      child: tieneGoogle
                          ? Row(
                              children: [
                                _IconoCaja(icono: Icons.mail_outline, colorScheme: colorScheme),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        usuario.emailGoogle!,
                                        style: GoogleFonts.jetBrainsMono(
                                          color: colorScheme.onSurface,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.check_circle,
                                              size: 14, color: colorScheme.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            "Verificada",
                                            style: AppTextStyles.tech(
                                              color: colorScheme.primary,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _cargandoAccion ? null : _desvincularGoogle,
                                  style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                                  icon: _cargandoAccion
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: colorScheme.error),
                                        )
                                      : const Icon(Icons.link_off, size: 16),
                                  label: const Text("Desvincular", style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Todavía no vinculaste ninguna cuenta de Google. Podés usar "
                                  "cualquier correo (no tiene que ser el de Nuevatel) para entrar "
                                  "más rápido la próxima vez.",
                                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    onPressed: _cargandoAccion ? null : _vincularGoogle,
                                    icon: _cargandoAccion
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.link),
                                    label: const Text("Vincular cuenta de Google"),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 24),
                    _TituloSeccion(texto: "SEGURIDAD Y DATOS", colorScheme: colorScheme),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _AccionRapida(
                            icono: Icons.key,
                            texto: "Actualizar clave",
                            colorScheme: colorScheme,
                            onTap: _irAActualizarClave,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AccionRapida(
                            icono: Icons.history,
                            texto: "Log de accesos",
                            colorScheme: colorScheme,
                            onTap: _mostrarLogProximamente,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Card translucida con blur de fondo (glassmorphism), como el resto del
/// "NOC Control Room" que ya usa la app en modo oscuro.
class _GlassCard extends StatelessWidget {
  final Widget child;
  final ColorScheme colorScheme;
  final Color? bordeIzquierdo;

  const _GlassCard({required this.child, required this.colorScheme, this.bordeIzquierdo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            boxShadow: bordeIzquierdo != null
                ? [BoxShadow(color: bordeIzquierdo!.withValues(alpha: 0.08), blurRadius: 16)]
                : null,
          ),
          child: bordeIzquierdo == null
              ? child
              : Row(
                  children: [
                    Container(
                      width: 3,
                      constraints: const BoxConstraints(minHeight: 40),
                      decoration: BoxDecoration(
                        color: bordeIzquierdo,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: child),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final String texto;
  final ColorScheme colorScheme;

  const _TituloSeccion({required this.texto, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        texto,
        style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 10),
      ),
    );
  }
}

class _IconoCaja extends StatelessWidget {
  final IconData icono;
  final ColorScheme colorScheme;

  const _IconoCaja({required this.icono, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icono, color: colorScheme.primary, size: 20),
    );
  }
}

/// Punto que titila suavemente, como el indicador "sincronizado" del mockup.
class _PuntoPulsante extends StatefulWidget {
  final Color color;

  const _PuntoPulsante({required this.color});

  @override
  State<_PuntoPulsante> createState() => _PuntoPulsanteState();
}

class _PuntoPulsanteState extends State<_PuntoPulsante> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _AvatarChico extends StatelessWidget {
  final String inicial;
  final ColorScheme colorScheme;

  const _AvatarChico({required this.inicial, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        inicial,
        style: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  final String inicial;
  final String nombre;
  final String rol;
  final ColorScheme colorScheme;

  const _TarjetaResumen({
    required this.inicial,
    required this.nombre,
    required this.rol,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      colorScheme: colorScheme,
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.primary, width: 2),
              boxShadow: [
                BoxShadow(color: colorScheme.primary.withValues(alpha: 0.25), blurRadius: 18),
              ],
            ),
            child: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                inicial,
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 30,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            nombre,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            rol,
            style: AppTextStyles.tech(color: colorScheme.onSurfaceVariant, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _AccionRapida extends StatelessWidget {
  final IconData icono;
  final String texto;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _AccionRapida({
    required this.icono,
    required this.texto,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: _GlassCard(
        colorScheme: colorScheme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: colorScheme.primary),
            const SizedBox(height: 10),
            Text(texto, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
