import "package:audioplayers/audioplayers.dart";

import "guardia_service.dart";

/// Reproduce el tono de alarma elegido en Configuracion de Guardia. Los
/// archivos son sonidos sinteticos empaquetados en assets/sounds/.
class AlarmaService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> reproducirUnaVez(String tono) async {
    final archivo = GuardiaService.archivosPorTono[tono] ??
        GuardiaService.archivosPorTono.values.first;
    await _player.stop();
    await _player.play(AssetSource(archivo));
  }

  Future<void> reproducirEnBucle(String tono) async {
    final archivo = GuardiaService.archivosPorTono[tono] ??
        GuardiaService.archivosPorTono.values.first;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource(archivo));
  }

  Future<void> detener() async {
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}
