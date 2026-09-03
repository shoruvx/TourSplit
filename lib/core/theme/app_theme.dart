import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryTeal = Color(0xFF00897B);
  static const Color primaryTealDark = Color(0xFF00695C);
  static const Color accent = Color(0xFF00897B);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color positive = Color(0xFF10B981);
  static const Color negative = Color(0xFFEF4444);

  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF64748B);

  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkText = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00897B), Color(0xFF0D9488)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00897B), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get lightTheme => _buildTheme(brightness: Brightness.light);
  static ThemeData get darkTheme => _buildTheme(brightness: Brightness.dark);

  static ThemeData _buildTheme({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primaryTeal,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      onSurface: isDark ? AppColors.darkText : AppColors.lightText,
      surfaceContainerHighest:
          isDark ? AppColors.darkCard : AppColors.lightCard,
    );

    final textTheme = TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 57,
        fontWeight: FontWeight.w700,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 45,
        fontWeight: FontWeight.w700,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      displaySmall: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 36,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      titleSmall: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color:
            isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      cardTheme: CardThemeData(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        foregroundColor: isDark ? AppColors.darkText : AppColors.lightText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? AppColors.darkSurface.withOpacity(0.5) : AppColors.lightBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(
          fontFamily: 'Outfit',
          color: isDark
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Outfit',
          color: isDark
              ? AppColors.darkTextSecondary
              : AppColors.lightTextSecondary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor:
            isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w400,
          fontSize: 12,
        ),
      ),
    );
  }
}
