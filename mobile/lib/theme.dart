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
/// vea siempre igual de critico.
class StatusColors {
  static const critico = Color(0xFFFF5252);
  static const advertencia = Color(0xFFFFB300);
  static const exitoso = Color(0xFF4CAF50);
  static const info = Color(0xFF2196F3);
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
  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Se genera un esquema base con el lima como semilla (rellena los roles
    // que no se pisan explicitamente) y despues, en oscuro, se reemplaza con
    // el esquema exacto "VIVA Operational Control" que dio el equipo.
    final base = ColorScheme.fromSeed(
        seedColor: BrandColors.lima, brightness: brightness);

    final colorScheme = isDark
        ? base.copyWith(
            primary: VivaColors.primary,
            onPrimary: VivaColors.onPrimary,
            primaryContainer: VivaColors.primaryContainer,
            onPrimaryContainer: VivaColors.onPrimaryContainer,
            secondary: VivaColors.secondary,
            onSecondary: VivaColors.onSecondary,
            secondaryContainer: VivaColors.secondaryContainer,
            onSecondaryContainer: VivaColors.onSecondaryContainer,
            tertiary: VivaColors.tertiary,
            onTertiary: VivaColors.onTertiary,
            tertiaryContainer: VivaColors.tertiaryContainer,
            onTertiaryContainer: VivaColors.onTertiaryContainer,
            error: VivaColors.error,
            onError: VivaColors.onError,
            errorContainer: VivaColors.errorContainer,
            onErrorContainer: VivaColors.onErrorContainer,
            surface: VivaColors.surface,
            onSurface: VivaColors.onSurface,
            surfaceDim: VivaColors.surfaceDim,
            surfaceBright: VivaColors.surfaceBright,
            surfaceContainerLowest: VivaColors.surfaceContainerLowest,
            surfaceContainerLow: VivaColors.surfaceContainerLow,
            surfaceContainer: VivaColors.surfaceContainer,
            surfaceContainerHigh: VivaColors.surfaceContainerHigh,
            surfaceContainerHighest: VivaColors.surfaceContainerHighest,
            onSurfaceVariant: VivaColors.onSurfaceVariant,
            outline: VivaColors.outline,
            outlineVariant: VivaColors.outlineVariant,
            inverseSurface: VivaColors.inverseSurface,
            onInverseSurface: VivaColors.inverseOnSurface,
            inversePrimary: VivaColors.inversePrimary,
            surfaceTint: VivaColors.surfaceTint,
          )
        : base.copyWith(
            primary: BrandColors.lima,
            onPrimary: BrandColors.negroVerdoso,
            primaryContainer: BrandColors.limaClaro,
            onPrimaryContainer: BrandColors.negroVerdoso,
            secondary: BrandColors.verdeOliva,
            onSecondary: Colors.white,
            secondaryContainer: BrandColors.limaClaro,
            onSecondaryContainer: BrandColors.negroVerdoso,
            surface: Colors.white,
            onSurface: BrandColors.negroVerdoso,
            surfaceContainerHigh: const Color(0xFFF3F5EA),
            surfaceContainerHighest: const Color(0xFFEAEDD9),
            onSurfaceVariant: BrandColors.verdeOscuro,
            outline: BrandColors.verdeOscuro.withValues(alpha: 0.4),
          );

    final camposFillColor =
        isDark ? VivaColors.surfaceContainerLow : const Color(0xFFF3F5EA);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: isDark ? 0 : 8,
        surfaceTintColor: Colors.transparent,
      ),
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
