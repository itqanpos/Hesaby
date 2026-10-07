// lib/core/preferences/app_preferences.dart

import 'package:flutter/material.dart';

/// Keys and helpers for the locally-persisted application preferences.
///
/// All values are stored as plain strings in [PreferencesStorage] so that
/// the same backend (SharedPreferences) can be reused everywhere.
abstract final class AppPreferences {
  // ---------------------------------------------------------------------------
  // Keys
  // ---------------------------------------------------------------------------

  static const String themeModeKey = 'app.theme_mode';
  static const String localeKey = 'app.locale';

  // ---------------------------------------------------------------------------
  // Theme mode
  // ---------------------------------------------------------------------------

  /// Parses a stored theme-mode name, defaulting to [ThemeMode.system].
  static ThemeMode parseThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// Converts a [ThemeMode] to its stable storage name.
  static String themeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  // ---------------------------------------------------------------------------
  // Locale
  // ---------------------------------------------------------------------------

  /// Parses a stored locale code (`'ar'` or `'en'`).
  ///
  /// Returns `null` when the value is missing or unrecognised, so the
  /// application can fall back to the platform locale.
  static Locale? parseLocale(String? raw) {
    switch (raw) {
      case 'ar':
        return const Locale('ar');
      case 'en':
        return const Locale('en');
      default:
        return null;
    }
  }

  /// Converts a [Locale] to its stable storage name.
  static String localeName(Locale locale) {
    return locale.languageCode == 'en' ? 'en' : 'ar';
  }
}
