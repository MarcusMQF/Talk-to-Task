import 'package:flutter/material.dart';

class AppTheme {
  // Primary brand colors
  static const Color grabGreen = Color(0xFF00B14F);
  static const Color grabBlack = Color(0xFF2A2A2A);
  
  // Secondary brand colors
  static const Color grabGreenLight = Color(0xFF4CD080);
  static const Color grabGreenDark = Color(0xFF008C3E);
  static const Color grabGray = Color(0xFFF7F7F7);
  static const Color grabGrayDark = Color(0xFF757575);
  
  // Semantic colors
  static const Color errorRed = Color(0xFFE53935);
  static const Color warningOrange = Color(0xFFFFA000);
  static const Color successGreen = Color(0xFF43A047);
  static const Color infoBlue = Color(0xFF2196F3);
  
  // Light theme
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: grabGreen,
    scaffoldBackgroundColor: grabGray,
    
    // App bar theme
    appBarTheme: const AppBarTheme(
      backgroundColor: grabGreen,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
    ),
    
    // Floating action button theme
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: grabGreen,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    
    // Button themes
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: grabGreen,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: grabGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: grabGreen,
        side: const BorderSide(color: grabGreen),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    
    // Card theme
    cardTheme: CardTheme(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
    ),
    
    // Text theme
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: grabBlack,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: grabBlack,
      ),
      titleSmall: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: grabBlack,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        color: grabBlack,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: grabBlack,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        color: grabGrayDark,
      ),
    ),
    
    // Input decoration theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: grabGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorRed, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    
    // Color scheme
    colorScheme: const ColorScheme.light(
      primary: grabGreen,
      secondary: grabGreenLight,
      tertiary: grabGreenDark,
      error: errorRed,
      surface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: grabBlack,
      onError: Colors.white,
    ),
  );

  // Dark theme
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: grabGreen,
    scaffoldBackgroundColor: const Color(0xFF121212),
    
    // App bar theme
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
    ),
    
    // Floating action button theme
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: grabGreen,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    
    // Button themes
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: grabGreen,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: grabGreenLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: grabGreenLight,
        side: const BorderSide(color: grabGreenLight),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    
    // Card theme
    cardTheme: CardTheme(
      elevation: 2,
      color: const Color(0xFF252525),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
    ),
    
    // Input decoration theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1E1E1E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: grabGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorRed, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    
    // Color scheme
    colorScheme: const ColorScheme.dark(
      primary: grabGreen,
      secondary: grabGreenLight,
      tertiary: grabGreenDark,
      error: errorRed,
      surface: Color(0xFF252525),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
      onError: Colors.white,
    ),
  );
} 