import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Soft Pastel Palette
  static const Color pastelLavender = Color(0xFF8B7FF8);       // Gentle Lavender Primary
  static const Color pastelLavenderLight = Color(0xFFEDE9FE);  // Very soft lavender background tint
  static const Color pastelBlue = Color(0xFF60A5FA);           // Calm Soft Blue
  static const Color pastelBlueLight = Color(0xFFEFF6FF);      // Soft baby blue tint
  static const Color pastelMint = Color(0xFF34D399);           // Soft Mint Green for Credit/Balance
  static const Color pastelMintLight = Color(0xFFECFDF5);      // Mint background tint
  static const Color pastelPeach = Color(0xFFFB923C);          // Soft Warm Peach
  static const Color pastelPeachLight = Color(0xFFFFF7ED);     // Peach background tint
  static const Color pastelPink = Color(0xFFF472B6);           // Soft Rose Pink
  static const Color pastelPinkLight = Color(0xFFFDF2F8);      // Soft pink tint
  static const Color pastelCoral = Color(0xFFF87171);          // Soft Coral for Debits & Over budget
  static const Color pastelCoralLight = Color(0xFFFEF2F2);     // Soft coral background tint

  // Neutral Backgrounds & Cards
  static const Color appBackground = Color(0xFFF8F9FE);        // Very calm, airy pastel ivory-white
  static const Color cardBackground = Color(0xFFFFFFFF);       // Clean crisp white
  static const Color cardBorder = Color(0xFFE2E8F0);           // Subtle soft border
  static const Color surfaceMuted = Color(0xFFF1F4F9);         // Soft input / surface fill
  static const Color surfaceVariant = surfaceMuted;
  static const Color borderColor = cardBorder;

  // Dark, highly readable text colors
  static const Color textPrimary = Color(0xFF1E293B);          // Deep Slate
  static const Color textSecondary = Color(0xFF475569);        // Medium Slate
  static const Color textMuted = Color(0xFF64748B);            // Subtle Slate

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: appBackground,
    colorScheme: const ColorScheme.light(
      primary: pastelLavender,
      secondary: pastelMint,
      tertiary: pastelBlue,
      error: pastelCoral,
      surface: cardBackground,
      onSurface: textPrimary,
      onPrimary: Colors.white,
    ),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.outfit(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: 0.3,
      ),
      iconTheme: const IconThemeData(color: textPrimary),
      shape: const Border(
        bottom: BorderSide(color: cardBorder, width: 1),
      ),
    ),
    cardTheme: CardThemeData(
      color: cardBackground,
      elevation: 0,
      shadowColor: pastelLavender.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: cardBorder, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: cardBorder, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: cardBorder, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: pastelLavender, width: 2),
      ),
      labelStyle: const TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: pastelLavender,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: GoogleFonts.outfit(
        fontSize: 19,
        fontWeight: FontWeight.bold,
        color: textPrimary,
      ),
      contentTextStyle: GoogleFonts.outfit(
        fontSize: 14,
        color: textSecondary,
        height: 1.5,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: textPrimary,
      contentTextStyle: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardBackground,
      surfaceTintColor: Colors.transparent,
      indicatorColor: pastelLavenderLight,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: pastelLavender,
          );
        }
        return GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: pastelLavender);
        }
        return const IconThemeData(color: textMuted);
      }),
    ),
  );
}
