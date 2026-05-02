import 'package:flutter/material.dart';

abstract class AppColors {
  static const primary   = Color(0xFF1A56DB);   // deep blue
  static const secondary = Color(0xFF0E9F6E);   // green
  static const warning   = Color(0xFFF05252);   // red
  static const caution   = Color(0xFFFF8A4C);   // amber-orange

  // Status colors — used on vehicle cards
  static const statusNotStarted = Color(0xFFE53E3E);   // red
  static const statusInProgress = Color(0xFFD97706);   // yellow/amber
  static const statusCompleted  = Color(0xFF059669);   // green

  static const surface    = Color(0xFFF9FAFB);
  static const cardBg     = Color(0xFFFFFFFF);
  static const border     = Color(0xFFE5E7EB);
  static const textPrimary   = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);

  // Dark variants
  static const darkSurface = Color(0xFF111827);
  static const darkCard    = Color(0xFF1F2937);
}

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardTheme(
      color: AppColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );

  static ThemeData get dark => light.copyWith(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkSurface,
    cardTheme: light.cardTheme.copyWith(color: AppColors.darkCard),
  );
}

// ─────────────────────────────────────────────
// Status color helpers
// ─────────────────────────────────────────────

Color jobCardStatusColor(String status) => switch (status) {
  'in_progress' => AppColors.statusInProgress,
  'completed'   => AppColors.statusCompleted,
  'on_hold'     => Colors.purple,
  'cancelled'   => Colors.grey,
  _             => AppColors.statusNotStarted,
};

Color taskStatusColor(String status) => switch (status) {
  'in_progress' => AppColors.statusInProgress,
  'completed'   => AppColors.statusCompleted,
  'cancelled'   => Colors.grey,
  _             => AppColors.statusNotStarted,
};

String jobCardStatusLabel(String status) => switch (status) {
  'in_progress' => 'In Progress',
  'completed'   => 'Completed',
  'on_hold'     => 'On Hold',
  'cancelled'   => 'Cancelled',
  _             => 'Pending',
};
