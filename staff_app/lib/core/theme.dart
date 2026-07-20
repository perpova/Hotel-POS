import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color bgDeep = Color(0xFF090D16);
  static const Color bgPrimary = Color(0xFF0F172A);
  static const Color bgCard = Color(0xFF1E293B);
  static const Color bgCardAlt = Color(0xFF334155);

  static const Color primary = Color(0xFF38BDF8); // Electric Sky Blue
  static const Color primaryGlow = Color(0x3038BDF8);

  static const Color success = Color(0xFF10B981); // Emerald Green (Clocked In)
  static const Color successGlow = Color(0x3010B981);

  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color error = Color(0xFFEF4444); // Crimson (Clocked Out)
  static const Color info = Color(0xFF8B5CF6); // Purple

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const Color border = Color(0xFF334155);
}

class AppTheme {
  static ThemeData get darkTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bgDeep,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.info,
        surface: AppColors.bgCard,
        onPrimary: Colors.black,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        titleLarge: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        bodyLarge: GoogleFonts.inter(color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.inter(color: AppColors.textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
