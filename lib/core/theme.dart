import 'package:flutter/material.dart';

class AppTheme {
  // New Color Palette from Image (Pastel)
  static const Color pastelPink = Color(0xFFFCE4EC);
  static const Color pastelMint = Color(0xFFE0F2F1);
  static const Color pastelYellow = Color(0xFFFFFDE7); // Background/Off-white
  static const Color pastelGreen = Color(0xFFC8E6C9);
  static const Color pastelLavender = Color(0xFFE1BEE7);
  static const Color pastelAqua = Color(0xFFB2EBF2);

  // Text Colors
  static const Color textDark = Color(0xFF2D3436);
  static const Color textLight = Color(0xFF636E72);

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: pastelYellow,
        colorScheme: ColorScheme.fromSeed(
          seedColor: pastelLavender,
          primary: Color(0xFFAD1457), // A darker pink for primary actions
          secondary: Color(0xFF00695C), // A darker teal/mint for secondary
          surface: Colors.white,
          onSurface: textDark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: pastelLavender,
          foregroundColor: textDark,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: textDark,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: pastelLavender),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: pastelLavender),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFAD1457), width: 2),
          ),
          hintStyle: const TextStyle(color: textLight),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: pastelPink,
            foregroundColor: textDark,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  // Keep darkTheme for compatibility but update to match palette style
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: pastelLavender,
          brightness: Brightness.dark,
          primary: pastelPink,
          secondary: pastelMint,
          surface: const Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2D2D2D),
          foregroundColor: pastelPink,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF2C2C2C),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2C2C2C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF444444)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF444444)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: pastelPink, width: 2),
          ),
        ),
      );
}
