// lib/app/theme/app_colors.dart
import 'package:flutter/material.dart';

/// Brand and semantic colour tokens for HESABI.
abstract final class AppColors {
  /// Primary brand colour of the HESABI identity.
  static const Color brandPrimary = Color(0xFF0F7B6C);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFED6C02);
  static const Color danger = Color(0xFFD32F2F);
  static const Color info = Color(0xFF0288D1);

  static const Color lightBackground = Color(0xFFF5F7F7);
  static const Color lightSurface = Color(0xFFFFFFFF);

  static const Color darkBackground = Color(0xFF0F1413);
  static const Color darkSurface = Color(0xFF171D1C);
}
