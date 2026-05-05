import 'package:flutter/material.dart';

class ZTheme {
  static Color get bg => const Color(0xFF121212);
  static Color get surface => const Color(0xFF1E1E1E);
  static Color get card => const Color(0xFF2C2C2C);
  static Color get cardHover => const Color(0xFF3A3A3A);
  static Color get border => const Color(0xFF3A3A3A);
  static Color get borderLight => const Color(0xFF4A4A4A);
  static Color get accent => const Color(0xFF4F79D4);
  static Color get accentBright => const Color(0xFF6B93F0);
  static Color get accentDim => accent.withOpacity(0.15);
  static Color get textPrimary => const Color(0xFFE8ECF4);
  static Color get textSecondary => const Color(0xFF8895AA);
  static Color get textTertiary => const Color(0xFF4A5568);
  static Color get danger => const Color(0xFFE85A6A);
  static Color get success => const Color(0xFF4CAF82);
  static Color get warning => const Color(0xFFE8A84F);

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    primaryColor: accent,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: surface,
      background: bg,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      centerTitle: true,
    ),
    tabBarTheme: const TabBarTheme(
      labelColor: accent,
      unselectedLabelColor: textTertiary,
      indicatorColor: accent,
    ),
  );
}