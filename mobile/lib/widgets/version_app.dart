import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";

/// Muestra la versión real de la app (la de pubspec.yaml, leída del paquete
/// instalado) en vez de un texto escrito a mano que se quedaba viejo.
class VersionApp extends StatelessWidget {
  const VersionApp({super.key, this.style, this.prefijo = "v"});

  final TextStyle? style;
  final String prefijo;

  static final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final version = snapshot.data?.version;
        return Text(
          version == null ? "" : "$prefijo$version".toUpperCase(),
          style: style,
        );
      },
    );
  }
}
