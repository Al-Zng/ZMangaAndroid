import 'package:flutter/material.dart';

class AppTheme {
  static const Color bg = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF161616);
  static const Color card = Color(0xFF1C1C1C);
  static const Color cardHover = Color(0xFF242424);
  static const Color border = Color(0xFF2A2A2A);
  static const Color borderLight = Color(0xFF383838);
  static const Color accent = Color(0xFFF5A623);
  static const Color accentBright = Color(0xFFFFB940);
  static Color accentDim = const Color(0xFFF5A623).withOpacity(0.15);
  static const Color textPrimary = Color(0xFFF0F0F0);
  static const Color textSecondary = Color(0xFF8A8A8A);
  static const Color textTertiary = Color(0xFF4A4A4A);
  static const Color danger = Color(0xFFE85A6A);
  static const Color success = Color(0xFF4CAF82);
  static const Color warning = Color(0xFFF5A623);

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFF5A623), Color(0xFFE8850A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

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
        tabBarTheme: const TabBarThemeData(
          labelColor: accent,
          unselectedLabelColor: textTertiary,
          indicatorColor: accent,
        ),
      );
}