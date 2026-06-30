import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static int dynamicPrimaryValue = 0xFFFF1B6B;

  // Brand Harmonious Palette
  static Color get primary => Color(dynamicPrimaryValue);       // Dynamic Primary Color (Defaults to FoodKing Pink)
  static const Color secondary = Color(0xFF4F46E5);     // Sleek Indigo
  static const Color accent = Color(0xFF10B981);        // Emerald Green (Success)
  static const Color warning = Color(0xFFFBBF24);       // Amber Yellow (Billing)
  static const Color danger = Color(0xFFEF4444);        // Ruby Red (Seated)
  
  static const Color bgLight = Color(0xFFF8FAFC);       // Soft slate background
  static const Color cardLight = Colors.white;
  static const Color textLightPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textLightSecondary = Color(0xFF64748B); // Slate 500

  // Gradients for modern elements (glassmorphic look / widgets)
  static Gradient get primaryGradient => LinearGradient(
    colors: [primary, const Color(0xFFFF781E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );



  static const Gradient indigoGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient emeraldGradient = LinearGradient(
    colors: [Color(0xFF34D399), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: secondary,
        error: danger,
        background: bgLight,
        surface: cardLight,
      ),
      scaffoldBackgroundColor: bgLight,
      textTheme: TextTheme(
        displayLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textLightPrimary,
        ),
        headlineMedium: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textLightPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textLightPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textLightPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 15,
          color: textLightPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          color: textLightSecondary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: textLightSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: textLightSecondary.withOpacity(0.7), fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
