import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// MindVault color system
class AppColors {
  AppColors._();

  // Seed colors
  static const Color primarySeed = Color(0xFF6750A4);
  static const Color secondarySeed = Color(0xFF7C5CBF);
  static const Color tertiarySeed = Color(0xFF00BFA5);

  // Brand colors
  static const Color brand = Color(0xFF6750A4);
  static const Color brandLight = Color(0xFF9A82DB);
  static const Color brandDark = Color(0xFF3F2B72);

  // Accent
  static const Color accent = Color(0xFF00BFA5);
  static const Color accentLight = Color(0xFF5DF2D6);
  static const Color accentDark = Color(0xFF008E76);

  // Semantic
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFED6C02);
  static const Color error = Color(0xFFD32F2F);
  static const Color info = Color(0xFF0288D1);

  // Review buttons
  static const Color reviewAgain = Color(0xFFD32F2F);
  static const Color reviewHard = Color(0xFFED6C02);
  static const Color reviewGood = Color(0xFF2E7D32);
  static const Color reviewEasy = Color(0xFF0288D1);

  // Streak
  static const Color streakFire = Color(0xFFFF6D00);

  // Graph
  static const Color graphNode = Color(0xFF6750A4);
  static const Color graphEdge = Color(0xFFBDBDBD);
  static const Color graphNodeActive = Color(0xFF00BFA5);

  // AMOLED
  static const Color amoledBlack = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF0A0A0A);
  static const Color amoledCard = Color(0xFF121212);
}

/// MindVault typography using Google Fonts Inter
class AppTypography {
  AppTypography._();

  static TextTheme get textTheme {
    return GoogleFonts.interTextTheme();
  }

  static TextStyle get displayLarge =>
      GoogleFonts.inter(fontSize: 57, fontWeight: FontWeight.w400);
  static TextStyle get displayMedium =>
      GoogleFonts.inter(fontSize: 45, fontWeight: FontWeight.w400);
  static TextStyle get displaySmall =>
      GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w400);

  static TextStyle get headlineLarge =>
      GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w600);
  static TextStyle get headlineMedium =>
      GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w600);
  static TextStyle get headlineSmall =>
      GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600);

  static TextStyle get titleLarge =>
      GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600);
  static TextStyle get titleMedium =>
      GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600);
  static TextStyle get titleSmall =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600);

  static TextStyle get bodyLarge =>
      GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400);
  static TextStyle get bodyMedium =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400);
  static TextStyle get bodySmall =>
      GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400);

  static TextStyle get labelLarge =>
      GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500);
  static TextStyle get labelMedium =>
      GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500);
  static TextStyle get labelSmall =>
      GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500);
}
