import 'package:flutter/material.dart';

/// Design Tokens para los Colores de GravitySync.
/// Centraliza la paleta para facilitar el modo oscuro/claro y la accesibilidad.
class AppColors {
  // Brand Colors (Primarios)
  static const Color primaryBase = Color(
    0xFF6B4EFF,
  ); // Un violeta/azul vibrante estilo AI
  static const Color primaryDark = Color(0xFF4A34CC);
  static const Color primaryLight = Color(0xFFA18BFF);

  // Status Colors (Feedback)
  static const Color statusOnline = Color(0xFF10B981); // Emerald
  static const Color statusOffline = Color(0xFFEF4444); // Red
  static const Color statusWarning = Color(0xFFF59E0B); // Amber

  // Background & Surfaces (ChatCoder AI Studio)
  static const Color background = Color(
    0xFF0F0F1A,
  ); // Deep Dark / Casi negro azulado
  static const Color surface = Color(0xFF14142D); // Tarjetas principales
  static const Color surfaceVariant = Color(0xFF1C1C3E); // Sub-elementos

  // Material 3 / System
  static const Color error = statusOffline;
  static const Color onPrimary = Colors.white;
  static const Color textPrimary = Color(0xFFF3F4F6); // Gris súper claro
  static const Color textSecondary = Color(0xFF9CA3AF); // Gris medio
  static const Color textMuted = Color(0xFF6B7280);

  // Borders & Dividers
  static const Color border = Color(0xFF272740);

  // Elementos Complejos de UI (ChatCoder)
  static const LinearGradient senderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6200EA), // Deep Purple Accent
      Color(0xFF0D0DF2), // Neon Blue
    ],
  );
}
