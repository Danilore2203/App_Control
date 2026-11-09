import "package:flutter/material.dart";

import "../models/usuario.dart";
import "../services/api_service.dart";
import "../services/auth_service.dart";
import "../theme.dart";
import "../widgets/fondo_app.dart";
import "../widgets/titulo_seccion.dart";
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final usuario = _usuario;
    final tieneGoogle = usuario?.emailGoogle != null;
    final inicial = (usuario?.nombre?.trim().isNotEmpty ?? false)
        ? usuario!.nombre!.trim()[0].toUpperCase()
        : (usuario?.username.isNotEmpty ?? false)
            ? usuario!.username[0].toUpperCase()
            : "?";

    return Scaffold(
      appBar: AppBar(title: const Text("Mi cuenta")),
      body: _cargandoPerfil
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_error != null) ...[
                  MensajeInline(_error!),
                  const SizedBox(height: 16),
                ],
                if (usuario != null) ...[
                  _TarjetaPerfil(
                    inicial: inicial,
                    nombre: usuario.nombre ?? usuario.username,
                    username: usuario.username,
                    esAdmin: usuario.esAdmin,
                  ),
                  const SizedBox(height: 22),
                  const TituloSeccion("Cuenta corporativa"),
                  const SizedBox(height: 10),
                  Vidrio(
                    padding: const EdgeInsets.all(14),
                    blur: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CajaIcono(Icons.apartment_rounded),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                usuario.nombre ?? usuario.username,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                usuario.email ?? "@${usuario.username}",
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const _PuntoPulsante(color: StatusColors.exitoso),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Sincronizado con Active Directory",
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
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
                  const SizedBox(height: 22),
                  const TituloSeccion("Cuenta de Google"),
                  const SizedBox(height: 10),
                  if (tieneGoogle)
                    FilaOpcion(
                      icono: Icons.mail_outline_rounded,
                      titulo: usuario.emailGoogle!,
                      subtitulo: "Verificada · podés entrar con Google",
                      color: StatusColors.exitoso,
                      trailing: TextButton.icon(
                        onPressed: _cargandoAccion ? null : _desvincularGoogle,
                        style: TextButton.styleFrom(foregroundColor: StatusColors.critico),
                        icon: _cargandoAccion
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: StatusColors.critico),
                              )
                            : const Icon(Icons.link_off_rounded, size: 16),
                        label: const Text("Quitar"),
                      ),
                    )
                  else
                    Vidrio(
                      padding: const EdgeInsets.all(16),
                      blur: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Todavía no vinculaste ninguna cuenta de Google. Podés usar "
                            "cualquier correo (no tiene que ser el de Nuevatel) para entrar "
                            "más rápido la próxima vez.",
                            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.4),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: _cargandoAccion ? null : _vincularGoogle,
                              icon: _cargandoAccion
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.link_rounded, size: 18),
                              label: const Text("Vincular cuenta de Google"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 22),
                  const TituloSeccion("Seguridad"),
                  const SizedBox(height: 10),
                  FilaOpcion(
                    icono: Icons.key_rounded,
                    titulo: "Actualizar contraseña",
                    subtitulo: "Cambiá la clave con la que entrás a la app",
                    onTap: _irAActualizarClave,
                  ),
                  const SizedBox(height: 8),
                  FilaOpcion(
                    icono: Icons.history_rounded,
                    titulo: "Log de accesos",
                    subtitulo: "Próximamente",
                    onTap: _mostrarLogProximamente,
                  ),
                ],
              ],
            ),
    );
  }
}

class _TarjetaPerfil extends StatelessWidget {
  final String inicial;
  final String nombre;
  final String username;
  final bool esAdmin;

  const _TarjetaPerfil({
    required this.inicial,
    required this.nombre,
    required this.username,
    required this.esAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary.withValues(alpha: 0.16),
              border: Border.all(color: colorScheme.primary, width: 2),
              boxShadow: [
                BoxShadow(color: colorScheme.primary.withValues(alpha: 0.3), blurRadius: 22, spreadRadius: -2),
              ],
            ),
            child: Text(
              inicial,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: acentoTinta(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            nombre,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            "@$username",
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          PillEstado(
            esAdmin ? "Administrador" : "Monitoreo y alertas",
            color: esAdmin ? acentoTinta(context) : colorScheme.onSurfaceVariant,
            icono: esAdmin ? Icons.verified_rounded : Icons.shield_outlined,
          ),
        ],
      ),
    );
  }
}

/// Punto que titila suavemente (indicador "sincronizado").
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
