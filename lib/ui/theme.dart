import 'package:flutter/material.dart';

class SensioTheme {
  // Deep dark palette
  static const Color background = Color(0xFF0F172A); // Slate 900
  static const Color surface = Color(0xFF1E293B);    // Slate 800
  static const Color surfaceLight = Color(0xFF334155);// Slate 700
  static const Color border = Color(0xFF475569);      // Slate 600

  // Signal & Status Palette
  static const Color ppgSignal = Color(0xFF38BDF8);   // Sky 400
  static const Color sigmotSignal = Color(0xFFA855F7);// Purple 500
  static const Color systolicPeak = Color(0xFFF43F5E);// Rose 500
  static const Color goodPulse = Color(0xFF10B981);   // Emerald 500
  static const Color rejectNoise = Color(0xFFF59E0B); // Amber 500
  static const Color badArtifact = Color(0xFFEF4444); // Red 500
  static const Color accent = Color(0xFF06B6D4);      // Cyan 500

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: ppgSignal,
        surface: surface,
        error: badArtifact,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF334155), width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: Color(0xFF94A3B8),
        indicatorColor: accent,
        dividerColor: Colors.transparent,
      ),
    );
  }
}
