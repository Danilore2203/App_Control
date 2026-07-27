import "package:flutter/material.dart";

import "../models/usuario.dart";
import "../screens/bitacora_screen.dart";
import "../screens/configuracion_guardia_screen.dart";
import "../screens/solicitudes_screen.dart";
import "../services/auth_service.dart";
import "../screens/login_screen.dart";

/// Menu lateral: encabezado de marca, secciones de navegacion (Monitoreo,
/// y Administracion si corresponde), y cerrar sesion abajo.
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
    await AuthService().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            _Encabezado(colorScheme: colorScheme, usuario: usuario),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _SeccionTitulo(texto: "MONITOREO"),
                  ListTile(
                    leading: const Icon(Icons.checklist),
                    title: const Text("Controles"),
                    selected: tabActual == 0,
                    selectedTileColor:
                        colorScheme.primaryContainer.withValues(alpha: 0.4),
                    onTap: () {
                      onSeleccionarTab(0);
                      Navigator.of(context).pop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_active),
                    title: const Text("Alertas"),
                    selected: tabActual == 1,
                    selectedTileColor:
                        colorScheme.primaryContainer.withValues(alpha: 0.4),
                    onTap: () {
                      onSeleccionarTab(1);
                      Navigator.of(context).pop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text("Configuración de guardia"),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ConfiguracionGuardiaScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text("Bitácora de errores"),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const BitacoraScreen()),
                      );
                    },
                  ),
                  if (usuario?.esAdmin ?? false) ...[
                    const Divider(),
                    const _SeccionTitulo(texto: "ADMINISTRACION"),
                    ListTile(
                      leading: const Icon(Icons.how_to_reg_outlined),
                      title: const Text("Solicitudes de acceso"),
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SolicitudesScreen()),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: ListTile(
                leading: Icon(Icons.logout, color: colorScheme.error),
                title: Text("Cerrar sesión",
                    style: TextStyle(color: colorScheme.error)),
                onTap: () => _cerrarSesion(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  final ColorScheme colorScheme;
  final Usuario? usuario;

  const _Encabezado({required this.colorScheme, required this.usuario});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.primaryContainer],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.onPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.shield_moon,
                      size: 24, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "CONTROLES",
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        "MONITOREO Y ALERTAS",
                        style: TextStyle(
                          color: colorScheme.onPrimary.withValues(alpha: 0.8),
                          fontSize: 10,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (usuario != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person, size: 18, color: colorScheme.onPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        usuario!.nombre ?? usuario!.username,
                        style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (usuario!.esAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "ADMIN",
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeccionTitulo extends StatelessWidget {
  final String texto;

  const _SeccionTitulo({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
