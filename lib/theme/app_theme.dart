import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ─── Colors (مطابق iOS ZTheme) ────────────────────────────────────
  static const Color bg      = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF161616);
  static const Color card    = Color(0xFF1C1C1C);
  static const Color border  = Color(0xFF2A2A2A);
  static const Color accent       = Color(0xFFF5A623);
  static const Color accentBright = Color(0xFFFFB940);
  static const Color textPrimary   = Color(0xFFF0F0F0);
  static const Color textSecondary = Color(0xFF8A8A8A);
  static const Color textTertiary  = Color(0xFF4A4A4A);
  static const Color danger  = Color(0xFFE85A6A);
  static const Color success = Color(0xFF4CAF82);

  static Color get accentDim => accent.withOpacity(0.15);

  // ─── Typography (Inter — أقرب خط لـ SF Pro على أندرويد) ──────────
  static TextTheme get _textTheme => GoogleFonts.interTextTheme(
    const TextTheme(
      bodyLarge:   TextStyle(color: textPrimary),
      bodyMedium:  TextStyle(color: textPrimary),
      bodySmall:   TextStyle(color: textSecondary),
      labelLarge:  TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleLarge:  TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    primaryColor: accent,
    textTheme: _textTheme,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: surface,
      background: bg,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: accent,
      unselectedItemColor: textTertiary,
      selectedLabelStyle: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500),
      unselectedLabelStyle: GoogleFonts.inter(fontSize: 10),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: accentDim,
      labelStyle: const TextStyle(color: accent, fontSize: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith((s) =>
          s.contains(MaterialState.selected) ? accent : Colors.grey[600]),
      trackColor: MaterialStateProperty.resolveWith((s) =>
          s.contains(MaterialState.selected) ? accent.withOpacity(0.4) : Colors.grey[800]),
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
    ),
  );
}
