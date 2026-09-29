// lib/app/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Central Material 3 theme definition for HESABI.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isLight = brightness == Brightness.light;

    final ColorScheme colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.brandPrimary,
          brightness: brightness,
        ).copyWith(
          error: AppColors.danger,
          surface: isLight ? AppColors.lightSurface : AppColors.darkSurface,
        );

    final TextTheme baseTextTheme = isLight
        ? const Typography.material2021().black
        : const Typography.material2021().white;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isLight
          ? AppColors.lightBackground
          : AppColors.darkBackground,
      textTheme: GoogleFonts.cairoTextTheme(baseTextTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: isLight
            ? AppColors.lightSurface
            : AppColors.darkSurface,
        foregroundColor: colorScheme.onSurface,
      ),
    );
  }
}
