import 'package:flutter/material.dart';

class ZTheme {
  ZTheme._();

  static const Color bg = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color card = Color(0xFF2C2C2C);
  static const Color cardHover = Color(0xFF3A3A3A);
  static const Color border = Color(0xFF3A3A3A);
  static const Color borderLight = Color(0xFF4A4A4A);
  static const Color accent = Color(0xFF4F79D4);
  static const Color accentBright = Color(0xFF6B93F0);
  static const Color textPrimary = Color(0xFFE8ECF4);
  static const Color textSecondary = Color(0xFF8895AA);
  static const Color textTertiary = Color(0xFF4A5568);
  static const Color danger = Color(0xFFE85A6A);
  static const Color success = Color(0xFF4CAF82);
  static const Color warning = Color(0xFFE8A84F);

  // accentDim is not const because it uses opacity; keep as static getter
  static Color get accentDim => accent.withOpacity(0.15);

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
        tabBarTheme: const TabBarThemeData(   // ✅ استخدم TabBarThemeData
          labelColor: accent,
          unselectedLabelColor: textTertiary,
          indicatorColor: accent,
        ),
      );
}