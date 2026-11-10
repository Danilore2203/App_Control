import "package:flutter/material.dart";

import "../models/usuario.dart";
import "../screens/ajustes_screen.dart";
import "../screens/infraestructura_screen.dart";
import "../screens/login_screen.dart";
import "../screens/mi_cuenta_screen.dart";
import "../screens/ra_screen.dart";
import "../screens/solicitudes_screen.dart";
import "../services/auth_service.dart";
import "../theme.dart";
import "titulo_seccion.dart";
import "version_app.dart";

/// Menu lateral: marca arriba, tarjeta del usuario, secciones de navegacion
/// (las cuatro pestanas, mas pantallas secundarias y administracion si
/// corresponde) y cerrar sesion abajo. Mismo lenguaje que el resto de la
/// app: filas redondeadas con icono en caja, la activa en lima.
class AppDrawer extends StatelessWidget {
  final Usuario? usuario;
  final int tabActual;
  final ValueChanged<int> onSeleccionarTab;

  const AppDrawer({
    super.key,
    required this.usuario,
    required this.tabActual,
    required this.onSeleccionarTab,
  });

  Future<void> _cerrarSesion(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Cerrar sesión?"),
        content: const Text("Vas a tener que ingresar de nuevo con tu usuario o con Google."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancelar")),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: StatusColors.critico),
            child: const Text("Cerrar sesión"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await AuthService().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _irATab(BuildContext context, int indice) {
    Navigator.of(context).pop();
    onSeleccionarTab(indice);
  }

  void _abrir(BuildContext context, Widget pantalla) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      width: 300,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _Marca(colorScheme: colorScheme),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _TarjetaUsuario(usuario: usuario),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                children: [
                  const _SeccionMenu("Monitoreo"),
                  _ItemMenu(
                    icono: Icons.grid_view_outlined,
                    iconoActivo: Icons.grid_view_rounded,
                    texto: "Controles",
                    activo: tabActual == 0,
                    onTap: () => _irATab(context, 0),
                  ),
                  _ItemMenu(
                    icono: Icons.notifications_outlined,
                    iconoActivo: Icons.notifications_rounded,
                    texto: "Alertas",
                    activo: tabActual == 1,
                    onTap: () => _irATab(context, 1),
                  ),
                  _ItemMenu(
                    icono: Icons.shield_outlined,
                    iconoActivo: Icons.shield_rounded,
                    texto: "Guardia",
                    activo: tabActual == 2,
                    onTap: () => _irATab(context, 2),
                  ),
                  _ItemMenu(
                    icono: Icons.menu_book_outlined,
                    iconoActivo: Icons.menu_book_rounded,
                    texto: "Bitácora de errores",
                    activo: tabActual == 3,
                    onTap: () => _irATab(context, 3),
                  ),
                  // Monitor RA: solo administradores (el backend tambien lo exige).
                  if (usuario?.esAdmin ?? false)
                    _ItemMenu(
                      icono: Icons.sync_rounded,
                      texto: "Monitor RA",
                      subtitulo: "Archivos FTP y actualizar ahora",
                      onTap: () => _abrir(context, const RaScreen()),
                    ),
                  const _SeccionMenu("Más"),
                  _ItemMenu(
                    icono: Icons.dns_outlined,
                    texto: "Infraestructura",
                    subtitulo: "Sesiones Netezza y PostgreSQL",
                    onTap: () => _abrir(context, const InfraestructuraScreen()),
                  ),
                  _ItemMenu(
                    icono: Icons.person_outline_rounded,
                    texto: "Mi cuenta",
                    onTap: () => _abrir(context, const MiCuentaScreen()),
                  ),
                  _ItemMenu(
                    icono: Icons.tune_rounded,
                    texto: "Ajustes",
                    onTap: () => _abrir(context, const AjustesScreen()),
                  ),
                  if (usuario?.esAdmin ?? false) ...[
                    const _SeccionMenu("Administración"),
                    _ItemMenu(
                      icono: Icons.how_to_reg_outlined,
                      texto: "Solicitudes de acceso",
                      onTap: () => _abrir(context, const SolicitudesScreen()),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ItemMenu(
                    icono: Icons.logout_rounded,
                    texto: "Cerrar sesión",
                    color: StatusColors.critico,
                    onTap: () => _cerrarSesion(context),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: VersionApp(
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: colorScheme.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Icon(Icons.insights_rounded, size: 26, color: colorScheme.onPrimary),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Controles",
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
            const Eyebrow("Monitoreo y alertas"),
          ],
        ),
      ],
    );
  }
}

class _TarjetaUsuario extends StatelessWidget {
  const _TarjetaUsuario({required this.usuario});

  final Usuario? usuario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nombre = (usuario?.nombre?.trim().isNotEmpty ?? false) ? usuario!.nombre!.trim() : usuario?.username ?? "";
    final detalle = usuario?.email ?? usuario?.emailGoogle ?? (usuario == null ? "Cargando perfil…" : "@${usuario!.username}");
    final inicial = nombre.isEmpty ? "?" : nombre[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary.withValues(alpha: 0.16),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Text(
              inicial,
              style: theme.textTheme.titleMedium?.copyWith(
                color: acentoTinta(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre.isEmpty ? "Usuario" : nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (usuario?.esAdmin ?? false) ...[
            const SizedBox(width: 8),
            PillEstado("Admin", color: acentoTinta(context), icono: Icons.verified_rounded),
          ],
        ],
      ),
    );
  }
}

class _SeccionMenu extends StatelessWidget {
  const _SeccionMenu(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Eyebrow(texto),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.icono,
    required this.texto,
    required this.onTap,
    this.iconoActivo,
    this.subtitulo,
    this.activo = false,
    this.color,
  });

  final IconData icono;
  final IconData? iconoActivo;
  final String texto;
  final String? subtitulo;
  final bool activo;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tono = color ?? colorScheme.primary;
    final colorTexto = color ?? colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: activo ? tono.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: activo ? tono.withValues(alpha: 0.45) : Colors.transparent),
            ),
            child: Row(
              children: [
                CajaIcono(
                  activo ? (iconoActivo ?? icono) : icono,
                  color: activo ? tono : (color ?? colorScheme.onSurfaceVariant),
                  tamano: 36,
                  tamanoIcono: 19,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        texto,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
                          color: activo ? acentoTinta(context) : colorTexto,
                        ),
                      ),
                      if (subtitulo != null)
                        Text(
                          subtitulo!,
                          style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                        ),
                    ],
                  ),
                ),
                if (activo)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: tono),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
