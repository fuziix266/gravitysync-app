import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Design Tokens para la Tipografía de GravitySync.
/// Utiliza Google Fonts (Inter) optimizado para legibilidad web/móvil.
class AppTypography {
  static TextTheme get textTheme {
    return GoogleFonts.interTextTheme(
      TextTheme(
        // Títulos grandes (App Bar, Headers vacíos)
        displayLarge: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),

        // Títulos medios (Nombres de hilos)
        titleLarge: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),

        // Texto general del chat
        bodyLarge: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          height: 1.4,
        ),

        // Texto secundario (último mensaje en la lista)
        bodyMedium: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          height: 1.3,
        ),

        // Etiquetas pequeñas (Fecha, horas)
        labelSmall: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // Estilo especial para bloques de código sueltos (monospace)
  static TextStyle get codeStyle {
    return GoogleFonts.firaCode(
      textStyle: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontSize: 14,
        height: 1.5,
      ),
    );
  }
}
