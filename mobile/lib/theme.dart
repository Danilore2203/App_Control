import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

/// Paleta de marca (5 colores exactos que dio el equipo).
class BrandColors {
  static const negroVerdoso = Color(0xFF232625);
  static const verdeOscuro = Color(0xFF3A4032);
  static const verdeOliva = Color(0xFF515931);
  static const lima = Color(0xFFC6D93B);
  static const limaClaro = Color(0xFFCAD959);
}

/// Colores funcionales de estado (error/advertencia/exito/info), fijos e
/// independientes del tema claro/oscuro para que un proceso "en error" se
/// vea siempre igual de critico. Son los mismos tokens --pm-* del monitor
/// web de OP (procesos.css), para que app y web se lean igual.
class StatusColors {
  static const critico = Color(0xFFD93448);
  static const advertencia = Color(0xFFC97F05);
  static const exitoso = Color(0xFF1F9D55);
  static const info = Color(0xFF1F6FD0);
  static const demorado = Color(0xFFE0A526);
  static const neutral = Color(0xFF7C877A);
}

/// Tokens del monitor web de OP (--pm-* en procesos.css), portados tal cual
/// para que la app se vea como la web: superficies "vidrio" translucidas
/// sobre un fondo con brillo lima, bordes finos, radio 16.
class OpTokens {
  // Claro
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surface2Light = Color(0xFFF6F8F3);
  static const surface3Light = Color(0xFFEEF2EA);
  static const pageLight = Color(0xFFEEF0F4);
  static const borderLight = Color(0x171F241F); // rgba(31,36,31,.09)
  static const borderStrongLight = Color(0x291F241F); // .16
  static const textLight = Color(0xFF1C211C);
  static const text2Light = Color(0xFF4A5549);
  static const text3Light = Color(0xFF7C877A);
  static const accentLight = Color(0xFFBFD730);
  static const accentInkLight = Color(0xFF55731A);
  static const glassLight = Color(0xC4FFFFFF); // rgba(255,255,255,.77)

  // Oscuro
  static const surfaceDark = Color(0xFF2B302E);
  static const surface2Dark = Color(0xFF333937);
  static const surface3Dark = Color(0xFF3A413E);
  static const pageDark = Color(0xFF141414);
  static const borderDark = Color(0x14E8EEE4); // rgba(232,238,228,.08)
  static const borderStrongDark = Color(0x29E8EEE4); // .16
  static const textDark = Color(0xFFE9EFE5);
  static const text2Dark = Color(0xFFC3CCBF);
  static const text3Dark = Color(0xFF8F9A8C);
  static const accentDark = Color(0xFFCFE24A);
  static const accentInkDark = Color(0xFFD7EB55);
  static const glassDark = Color(0xB32B302E); // rgba(43,48,46,.70)

  static const radius = 16.0;
}

/// Esquema de color exacto "VIVA Operational Control" (NOC Control Room)
/// para el modo oscuro: cada valor es el hex que dio el equipo, sin pasar
/// por un ColorScheme.fromSeed que los aproxima.
class VivaColors {
  static const surface = Color(0xFF0F150F);
  static const surfaceDim = Color(0xFF0F150F);
  static const surfaceBright = Color(0xFF353B34);
  static const surfaceContainerLowest = Color(0xFF0A100A);
  static const surfaceContainerLow = Color(0xFF171D17);
  static const surfaceContainer = Color(0xFF1B211B);
  static const surfaceContainerHigh = Color(0xFF252C25);
  static const surfaceContainerHighest = Color(0xFF303630);
  static const onSurface = Color(0xFFDEE4DA);
  static const onSurfaceVariant = Color(0xFFC7C8AF);
  static const inverseSurface = Color(0xFFDEE4DA);
  static const inverseOnSurface = Color(0xFF2C322B);
  static const outline = Color(0xFF90937B);
  static const outlineVariant = Color(0xFF464835);
  static const surfaceTint = Color(0xFFBAD22A);
  static const primary = Color(0xFFDBF44C);
  static const onPrimary = Color(0xFF2C3400);
  static const primaryContainer = Color(0xFFBFD730);
  static const onPrimaryContainer = Color(0xFF4F5B00);
  static const inversePrimary = Color(0xFF576400);
  static const secondary = Color(0xFFBFD047);
  static const onSecondary = Color(0xFF2D3400);
  static const secondaryContainer = Color(0xFF899909);
  static const onSecondaryContainer = Color(0xFF272D00);
  static const tertiary = Color(0xFFE3E9E6);
  static const onTertiary = Color(0xFF2C3230);
  static const tertiaryContainer = Color(0xFFC7CDCA);
  static const onTertiaryContainer = Color(0xFF515755);
  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
  static const errorContainer = Color(0xFF93000A);
  static const onErrorContainer = Color(0xFFFFDAD6);
}

/// Estilos de texto reutilizables que no vienen del TextTheme por defecto
/// (p.ej. las etiquetas tipo "panel tecnico" en mayusculas monoespaciadas
/// usadas en encabezados y titulos de seccion).
class AppTextStyles {
  static TextStyle tech({
    required Color color,
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = 1.4,
  }) {
    return GoogleFonts.jetBrainsMono(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }
}

/// Tema de la app: sigue automaticamente el modo claro/oscuro del celular
/// (ThemeMode.system en main.dart), usando siempre los colores de marca.
class AppTheme {
  /// Las pruebas lo ponen en false: google_fonts intenta descargar Inter y
  /// en el entorno de test no hay red ni assets, y falla el test entero.
  static bool usarGoogleFonts = true;

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Se genera un esquema base con el lima como semilla (rellena los roles
    // que no se pisan explicitamente) y despues, en oscuro, se reemplaza con
    // el esquema exacto "VIVA Operational Control" que dio el equipo.
    final base = ColorScheme.fromSeed(
        seedColor: BrandColors.lima, brightness: brightness);

    // Mapa de los tokens --pm-* del monitor web a los roles de Material:
    //   surface               -> fondo de pagina (se pinta con FondoApp)
    //   surfaceContainerHigh  -> "vidrio": tarjetas translucidas
    //   surfaceContainerHighest -> superficie 3 (chips, pills, inputs)
    //   onSurface / onSurfaceVariant / outline -> text / text-2 / text-3
    //   outlineVariant        -> borde fino
    final colorScheme = isDark
        ? base.copyWith(
            primary: OpTokens.accentDark,
            onPrimary: OpTokens.textLight,
            primaryContainer: OpTokens.accentDark.withValues(alpha: 0.18),
            onPrimaryContainer: OpTokens.accentInkDark,
            secondary: OpTokens.accentInkDark,
            onSecondary: OpTokens.textLight,
            secondaryContainer: OpTokens.surface3Dark,
            onSecondaryContainer: OpTokens.textDark,
            tertiary: OpTokens.text2Dark,
            error: const Color(0xFFFF8B98),
            onError: const Color(0xFF2A0D10),
            errorContainer: const Color(0x33D93448),
            onErrorContainer: const Color(0xFFFF8B98),
            surface: OpTokens.pageDark,
            onSurface: OpTokens.textDark,
            surfaceDim: OpTokens.pageDark,
            surfaceBright: OpTokens.surface3Dark,
            surfaceContainerLowest: OpTokens.pageDark,
            surfaceContainerLow: OpTokens.surfaceDark,
            surfaceContainer: OpTokens.surface2Dark,
            surfaceContainerHigh: OpTokens.glassDark,
            surfaceContainerHighest: OpTokens.surface3Dark,
            onSurfaceVariant: OpTokens.text2Dark,
            outline: OpTokens.text3Dark,
            outlineVariant: OpTokens.borderStrongDark,
            inverseSurface: OpTokens.textDark,
            onInverseSurface: OpTokens.surfaceDark,
            inversePrimary: OpTokens.accentInkLight,
            surfaceTint: Colors.transparent,
          )
        : base.copyWith(
            primary: OpTokens.accentLight,
            onPrimary: OpTokens.textLight,
            primaryContainer: OpTokens.accentLight.withValues(alpha: 0.2),
            onPrimaryContainer: OpTokens.accentInkLight,
            secondary: OpTokens.accentInkLight,
            onSecondary: Colors.white,
            secondaryContainer: OpTokens.surface3Light,
            onSecondaryContainer: OpTokens.textLight,
            tertiary: OpTokens.text2Light,
            error: const Color(0xFFD93448),
            onError: Colors.white,
            errorContainer: const Color(0xFFFDEAED),
            onErrorContainer: const Color(0xFFD93448),
            surface: OpTokens.pageLight,
            onSurface: OpTokens.textLight,
            surfaceDim: OpTokens.surface3Light,
            surfaceBright: Colors.white,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: OpTokens.surface2Light,
            surfaceContainer: OpTokens.surfaceLight,
            surfaceContainerHigh: OpTokens.glassLight,
            surfaceContainerHighest: OpTokens.surface3Light,
            onSurfaceVariant: OpTokens.text2Light,
            outline: OpTokens.text3Light,
            outlineVariant: OpTokens.borderStrongLight,
            inverseSurface: OpTokens.textLight,
            onInverseSurface: Colors.white,
            inversePrimary: OpTokens.accentInkDark,
            surfaceTint: Colors.transparent,
          );

    final camposFillColor = isDark ? OpTokens.surface2Dark : Colors.white;

    // Tipografia de toda la app: Inter, la misma del monitor web. La
    // monoespaciada (AppTextStyles.tech) queda solo para datos tecnicos
    // chicos, no para la jerarquia de las pantallas.
    final baseTextTheme = ThemeData(brightness: brightness, useMaterial3: true).textTheme;
    final textTheme = (usarGoogleFonts ? GoogleFonts.interTextTheme(baseTextTheme) : baseTextTheme).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      // El fondo real lo pinta FondoApp (gradiente + brillo lima + puntos),
      // envolviendo cada pantalla desde MaterialApp.builder: el Scaffold va
      // transparente para que las tarjetas "vidrio" dejen verlo.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: colorScheme.onSurface,
        ),
      ),
      // Tarjetas translucidas con borde fino, como .pm-panel en la web.
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OpTokens.radius),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? OpTokens.glassDark : OpTokens.glassLight,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primary,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? OpTokens.surfaceDark : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? OpTokens.surfaceDark : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? OpTokens.surfaceDark : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: camposFillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        prefixIconColor: colorScheme.onSurfaceVariant,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),
    );
  }
}
