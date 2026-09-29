// lib/core/storage/preferences_storage.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstraction over non-sensitive key/value persistence.
abstract interface class PreferencesStorage {
  Future<void> writeString({required String key, required String value});

  Future<String?> readString({required String key});

  Future<void> writeBool({required String key, required bool value});

  Future<bool?> readBool({required String key});

  Future<void> remove({required String key});

  Future<void> clear();
}

/// [SharedPreferences] backed implementation of [PreferencesStorage].
final class PreferencesStorageImpl implements PreferencesStorage {
  PreferencesStorageImpl(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<void> writeString({required String key, required String value}) =>
      _preferences.setString(key, value);

  @override
  Future<String?> readString({required String key}) async =>
      _preferences.getString(key);

  @override
  Future<void> writeBool({required String key, required bool value}) =>
      _preferences.setBool(key, value);

  @override
  Future<bool?> readBool({required String key}) async =>
      _preferences.getBool(key);

  @override
  Future<void> remove({required String key}) => _preferences.remove(key);

  @override
  Future<void> clear() => _preferences.clear();
}

/// Lazily resolved preferences storage.
final FutureProvider<PreferencesStorage> preferencesStorageProvider =
    FutureProvider<PreferencesStorage>((ref) async {
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  return PreferencesStorageImpl(preferences);
});
