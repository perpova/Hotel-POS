import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Background layers
  static const Color bgDeep = Color(0xFF070B14);
  static const Color bgPrimary = Color(0xFF0D1120);
  static const Color bgCard = Color(0xFF121929);
  static const Color bgCardAlt = Color(0xFF1A2340);
  static const Color bgOverlay = Color(0xFF1E2D45);

  // Brand colors
  static const Color primary = Color(0xFFF59E0B); // Amber
  static const Color primaryDark = Color(0xFFD97706);
  static const Color primaryGlow = Color(0x30F59E0B);

  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color successGlow = Color(0x2010B981);
  static const Color warning = Color(0xFFF97316);
  static const Color warningGlow = Color(0x30F97316);
  static const Color error = Color(0xFFEF4444);
  static const Color errorGlow = Color(0x30EF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoGlow = Color(0x303B82F6);

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF475569);

  // Borders & dividers
  static const Color border = Color(0xFF1E2D45);
  static const Color borderLight = Color(0xFF263552);

  // Chart palette
  static const List<Color> chartColors = [
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFF97316),
  ];
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark();
    return base.copyWith(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bgDeep,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.info,
        surface: AppColors.bgCard,
        error: AppColors.error,
        onPrimary: Colors.black,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.w700,
        ),
        displayMedium: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w600,
        ),
        titleMedium: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600,
        ),
        titleSmall: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500,
        ),
        bodyLarge: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
        bodySmall: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
        labelLarge: GoogleFonts.inter(
          color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgPrimary,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: const EdgeInsets.all(0),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgPrimary,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgCardAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgCardAlt,
        selectedColor: AppColors.primaryGlow,
        labelStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
