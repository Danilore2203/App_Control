class AppConfig {
  // IP de esta PC en la red local (misma WiFi que el celular), para probar
  // el APK instalado sin cable USB. Si esta PC cambia de IP (otra red,
  // reinicio de router), hay que actualizar esto y volver a compilar.
  // Cuando el backend tenga direccion final, cambiar por esa URL real.
  static const String apiBaseUrl = "http://10.47.19.180:8000";

  // Web Client ID generado por Firebase al activar Google como proveedor de
  // Authentication (Firebase Console > Authentication > Sign-in method > Google).
  static const String googleServerClientId =
      "983197006246-k3qveb7q27bi000384lt4c4j000ual79.apps.googleusercontent.com";
}
