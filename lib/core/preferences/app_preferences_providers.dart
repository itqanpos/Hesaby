// lib/core/preferences/app_preferences_providers.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_storage.dart';
import 'app_preferences.dart';

// ============================================================================
// Theme mode
// ============================================================================

/// Notifier for the application's theme mode.
///
/// Reads its initial value from storage; each write is persisted
/// optimistically (state first, then disk).
class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  bool _isDisposed = false;

  @override
  Future<ThemeMode> build() async {
    ref.onDispose(() => _isDisposed = true);

    final PreferencesStorage storage =
        await ref.watch(preferencesStorageProvider.future);
    final String? raw = await storage.readString(
      key: AppPreferences.themeModeKey,
    );
    return AppPreferences.parseThemeMode(raw);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final ThemeMode? previous = state.valueOrNull;
    if (!_isDisposed) {
      state = AsyncData<ThemeMode>(mode);
    }

    final PreferencesStorage storage =
        await ref.read(preferencesStorageProvider.future);

    try {
      await storage.writeString(
        key: AppPreferences.themeModeKey,
        value: AppPreferences.themeModeName(mode),
      );
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        if (previous != null) {
          state = AsyncData<ThemeMode>(previous);
        } else {
          state = AsyncError<ThemeMode>(error, stackTrace);
        }
      }
      rethrow;
    }
  }
}

/// Async holder of the current theme mode.
final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// ============================================================================
// Locale
// ============================================================================

/// Notifier for the application's preferred locale.
///
/// A `null` value means "follow the platform locale".
class LocaleNotifier extends AsyncNotifier<Locale?> {
  bool _isDisposed = false;

  @override
  Future<Locale?> build() async {
    ref.onDispose(() => _isDisposed = true);

    final PreferencesStorage storage =
        await ref.watch(preferencesStorageProvider.future);
    final String? raw = await storage.readString(
      key: AppPreferences.localeKey,
    );
    return AppPreferences.parseLocale(raw);
  }

  Future<void> setLocale(Locale? locale) async {
    final Locale? previous = state.valueOrNull;
    if (!_isDisposed) {
      state = AsyncData<Locale?>(locale);
    }

    final PreferencesStorage storage =
        await ref.read(preferencesStorageProvider.future);

    try {
      if (locale == null) {
        await storage.remove(key: AppPreferences.localeKey);
      } else {
        await storage.writeString(
          key: AppPreferences.localeKey,
          value: AppPreferences.localeName(locale),
        );
      }
    } catch (error) {
      // The stack trace is not used here; the state restore is the only
      // side-effect we care about.
      if (!_isDisposed) {
        state = AsyncData<Locale?>(previous);
      }
      rethrow;
    }
  }
}

/// Async holder of the current preferred locale (`null` = follow system).
final localeProvider =
    AsyncNotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
