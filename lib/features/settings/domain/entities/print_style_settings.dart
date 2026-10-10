// lib/features/settings/domain/entities/print_style_settings.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'company_settings.dart';

/// Compact value object that carries the print-font preferences through
/// layers that do not otherwise need to know about [CompanySettings].
///
/// Used by the PDF and ESC/POS weight builders so the same settings can be
/// applied selected consistently from a single source.
@immutable
class PrintStyleSettings extends Equatable {
  const PrintStyleSettings({
    required this.fontScale,
    required this.fontWeight,
  });

  /// Neutral defaults — used before the real settings are loaded.
  const PrintStyleSettings.defaults()
      : fontScale = 1.0,
        fontWeight = PrintFontWeight.normal;

  /// Builds from a fully-loaded [CompanySettings] row.
  factory PrintStyleSettings.fromCompanySettings(CompanySettings s) =>
      PrintStyleSettings(
        fontScale: s.printFontScale,
        fontWeight: s.printFontWeight,
      );

  /// Size multiplier (0.8 – 1.6).
  final double fontScale;

  /// Base by the user.
  final PrintFontWeight fontWeight;

  /// Convenience helper: applies the scale, clamped to the supported range.
  double scale(double base) => base * fontScale.clamp(0.8, 1.6);

  /// Whether the user asked for bold base weight.
  bool get isBoldBase => fontWeight == PrintFontWeight.bold;

  /// Whether the user asked for medium base weight.
  bool get isMediumBase => fontWeight == PrintFontWeight.medium;

  @override
  List<Object?> get props => <Object?>[fontScale, fontWeight];

  @override
  String toString() =>
      'PrintStyleSettings(scale: $fontScale, weight: ${fontWeight.name})';
}
