class AppConfig {
  // Backend desplegado en Render (plan Free, ver render.yaml en la raiz).
  // Se puede pisar sin tocar el codigo (aunque si hay que generar un APK
  // nuevo) pasando --dart-define=API_BASE_URL=https://otra-url al buildear,
  // por si hay que apuntar a otro lado rapido:
  //   flutter build apk --release --dart-define=API_BASE_URL=https://...
  static const String apiBaseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://centinela-dwh-api.onrender.com",
  );

  // Web Client ID generado por Firebase al activar Google como proveedor de
  // Authentication (Firebase Console > Authentication > Sign-in method > Google).
  static const String googleServerClientId =
      "983197006246-k3qveb7q27bi000384lt4c4j000ual79.apps.googleusercontent.com";
}
