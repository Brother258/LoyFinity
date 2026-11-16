import 'package:flutter/material.dart';

abstract final class LoyColors {
  static const navy = Color(0xFF0B2942);
  static const navySoft = Color(0xFF123B5D);
  static const blue = Color(0xFF1379C8);
  static const blueDark = Color(0xFF0B5EA8);
  static const blueTint = Color(0xFFEAF4FC);
  static const gold = Color(0xFFF3B800);
  static const green = Color(0xFF21865B);
  static const greenTint = Color(0xFFEAF7F0);
  static const ink = Color(0xFF142A3B);
  static const muted = Color(0xFF718292);
  static const canvas = Color(0xFFF6F8FA);
  static const line = Color(0xFFE7EDF2);
  static const danger = Color(0xFFB73B3B);
}

ThemeData buildLoyfinityTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: LoyColors.blue,
    primary: LoyColors.blue,
    secondary: LoyColors.gold,
    surface: Colors.white,
    error: LoyColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LoyColors.canvas,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: const AppBarTheme(
      backgroundColor: LoyColors.canvas,
      foregroundColor: LoyColors.navy,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: LoyColors.navy, letterSpacing: -0.4),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 31, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -1.0, color: LoyColors.navy),
      headlineMedium: TextStyle(fontSize: 25, height: 1.18, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: LoyColors.navy),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: LoyColors.navy),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: LoyColors.ink),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: LoyColors.ink),
      bodyMedium: TextStyle(fontSize: 13, height: 1.4, color: LoyColors.muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: LoyColors.muted, fontSize: 14),
      labelStyle: const TextStyle(color: LoyColors.muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: LoyColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: LoyColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: LoyColors.blue, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: LoyColors.danger)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: LoyColors.line)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: LoyColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LoyColors.navy,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: LoyColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: LoyColors.blueTint,
      selectedColor: LoyColors.blue,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: LoyColors.navy),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      side: BorderSide.none,
    ),
    dividerColor: LoyColors.line,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: LoyColors.blue,
      unselectedItemColor: LoyColors.muted,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      elevation: 0,
    ),
  );
}
