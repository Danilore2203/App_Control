import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../models/usuario.dart";
import "../services/api_service.dart";
import "../widgets/estado_vacio.dart";
import "../widgets/fondo_app.dart";
import "../widgets/titulo_seccion.dart";

/// Administración → Usuarios: cuando a alguien no le llega el correo para
/// cambiar la contraseña, un administrador genera aquí un código de un solo
/// uso y se lo pasa. La persona elige su contraseña nueva en la app
/// («Olvidé mi contraseña» → «Ya tengo un código»): el administrador no la ve.
class UsuariosAdminScreen extends StatefulWidget {
  const UsuariosAdminScreen({super.key, this.servicio});

  /// Para las pruebas; normalmente null.
  final ApiService? servicio;

  @override
  State<UsuariosAdminScreen> createState() => _UsuariosAdminScreenState();
}

class _UsuariosAdminScreenState extends State<UsuariosAdminScreen> {
  late final ApiService _api = widget.servicio ?? ApiService();
  final _buscar = TextEditingController();
  Timer? _espera;
  late Future<List<Usuario>> _usuarios = _api.buscarUsuarios("");
  int? _generando;

  @override
  void dispose() {
    _espera?.cancel();
    _buscar.dispose();
    super.dispose();
  }

  void _alEscribir(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final busqueda = _api.buscarUsuarios(texto.trim());
      setState(() {
        _usuarios = busqueda;
      });
    });
  }

  Future<void> _recargar() async {
    final busqueda = _api.buscarUsuarios(_buscar.text.trim());
    setState(() {
      _usuarios = busqueda;
    });
    await busqueda;
  }

  Future<void> _generar(Usuario u) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("¿Código para ${u.username}?"),
        content: const Text(
          "Se genera un código de un solo uso para que esa persona elija una contraseña nueva en la app. "
          "Cualquier código anterior deja de servir. Pásaselo solo a ella.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancelar")),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Generar")),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _generando = u.id);
    try {
      final r = await _api.generarCodigoRecuperacion(u.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _CodigoGenerado(usuario: u, codigo: r.codigo, minutos: r.minutos, expiraEn: r.expiraEn),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))));
    } finally {
      if (mounted) setState(() => _generando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Usuarios y contraseñas")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Column(
              children: [
                MensajeInline(
                  "Si a alguien no le llega el correo para cambiar su contraseña, genera aquí un código y "
                  "pásaselo. La persona elige su contraseña nueva en la app: tú no la ves.",
                  color: colorScheme.primary,
                  icono: Icons.info_outline,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key("buscar_usuarios"),
                  controller: _buscar,
                  onChanged: _alEscribir,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: "Buscar por usuario, nombre o correo",
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Usuario>>(
              future: _usuarios,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return EstadoVacio(
                    icono: Icons.cloud_off_rounded,
                    mensaje: "No se pudieron cargar los usuarios",
                    colorIcono: colorScheme.error,
                    onReintentar: _recargar,
                  );
                }
                final usuarios = snapshot.data ?? const <Usuario>[];
                if (usuarios.isEmpty) {
                  return EstadoVacio(
                    icono: Icons.person_search_rounded,
                    mensaje: "No hay usuarios con ese nombre",
                    colorIcono: colorScheme.outline,
                  );
                }
                return RefreshIndicator(
                  onRefresh: _recargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: usuarios.length,
                    itemBuilder: (context, i) {
                      final u = usuarios[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FilaUsuario(
                          usuario: u,
                          generando: _generando == u.id,
                          onGenerar: _generando == null && u.activo ? () => _generar(u) : null,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaUsuario extends StatelessWidget {
  const _FilaUsuario({required this.usuario, required this.generando, required this.onGenerar});

  final Usuario usuario;
  final bool generando;
  final VoidCallback? onGenerar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final u = usuario;
    final nombre = (u.nombre ?? "").trim().isEmpty ? u.username : u.nombre!.trim();
    return Vidrio(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      blur: 10,
      child: Row(
        children: [
          CajaIcono(Icons.person_outline_rounded, tamano: 36, tamanoIcono: 18,
              color: u.activo ? null : colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    if (u.esAdmin) ...[
                      const SizedBox(width: 6),
                      PillEstado("Admin", color: acentoTinta(context)),
                    ],
                    if (!u.activo) ...[
                      const SizedBox(width: 6),
                      PillEstado("Inactiva", color: colorScheme.outline),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  ["@${u.username}", if ((u.email ?? "").isNotEmpty) u.email!].join(" · "),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          generando
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: "Generar código para cambiar la contraseña",
                  onPressed: onGenerar,
                  icon: const Icon(Icons.key_rounded),
                ),
        ],
      ),
    );
  }
}

class _CodigoGenerado extends StatelessWidget {
  const _CodigoGenerado({required this.usuario, required this.codigo, required this.minutos, required this.expiraEn});

  final Usuario usuario;
  final String codigo;
  final int minutos;
  final DateTime expiraEn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hora = "${expiraEn.hour.toString().padLeft(2, "0")}:${expiraEn.minute.toString().padLeft(2, "0")}";
    return AlertDialog(
      title: Text("Código para ${usuario.username}"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: acentoTinta(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: acentoTinta(context).withValues(alpha: 0.35)),
            ),
            child: SelectableText(
              codigo,
              key: const Key("codigo_generado"),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text("Vale $minutos minutos (hasta las $hora) y sirve una sola vez.",
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          const Eyebrow("Qué tiene que hacer"),
          const SizedBox(height: 6),
          Text(
            "1. En la app, tocar «Olvidé mi contraseña».\n"
            "2. Escribir su usuario (${usuario.username}) y tocar «Ya tengo un código».\n"
            "3. Escribir este código y elegir su contraseña nueva.",
            style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: codigo));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código copiado")));
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text("Copiar"),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Listo")),
      ],
    );
  }
}
