// lib/core/cache/json_local_cache.dart

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

/// Generic JSON-based local cache backed by [SharedPreferences].
class JsonLocalCache {
  const JsonLocalCache(this._prefs);

  final SharedPreferences _prefs;

  static const int _schemaVersion = 1;

  String _key(String prefix, String companyId) =>
      'hesabi.cache.$prefix.$companyId';

  Future<void> saveList({
    required String prefix,
    required String companyId,
    required List<Map<String, Object?>> items,
  }) async {
    try {
      final String encoded = jsonEncode(<String, Object?>{
        'v': _schemaVersion,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'items': items,
      });
      await _prefs.setString(_key(prefix, companyId), encoded);
    } on Object catch (error) {
      AppLogger.warning(
        'JsonLocalCache: save failed for $prefix/$companyId: $error',
      );
    }
  }

  List<Map<String, dynamic>>? loadList({
    required String prefix,
    required String companyId,
  }) {
    try {
      final String? raw = _prefs.getString(_key(prefix, companyId));
      if (raw == null || raw.isEmpty) return null;

      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['v'] != _schemaVersion) return null;

      final Object? itemsRaw = decoded['items'];
      if (itemsRaw is! List) return null;

      return itemsRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } on Object catch (error) {
      AppLogger.warning(
        'JsonLocalCache: load failed for $prefix/$companyId: $error',
      );
      return null;
    }
  }

  DateTime? savedAt({
    required String prefix,
    required String companyId,
  }) {
    try {
      final String? raw = _prefs.getString(_key(prefix, companyId));
      if (raw == null) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Object? savedAtRaw = decoded['saved_at'];
      if (savedAtRaw is! String) return null;
      return DateTime.tryParse(savedAtRaw)?.toLocal();
    } on Object {
      return null;
    }
  }

  Future<void> clear({
    required String prefix,
    required String companyId,
  }) async {
    await _prefs.remove(_key(prefix, companyId));
  }

  Future<void> clearAllForCompany(String companyId) async {
    final String suffix = '.$companyId';
    final Iterable<String> keys = _prefs.getKeys().where(
      (k) => k.startsWith('hesabi.cache.') && k.endsWith(suffix),
    );
    for (final String key in keys.toList()) {
      await _prefs.remove(key);
    }
  }
}
