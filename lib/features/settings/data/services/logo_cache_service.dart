// lib/features/settings/data/services/logo_cache_service.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/logger.dart';

/// Caches the company logo bytes locally so printing does not depend on
/// the network.
///
/// The bytes are stored base64-encoded in [SharedPreferences]. This keeps
/// the implementation dependency-free and fast enough for typical logo
/// sizes (< 500 KB).
///
/// Lifecycle:
/// * After a successful upload → [save] stores the fresh bytes.
/// * After a logo delete → [clear] removes them.
/// * During printing → [load] returns the bytes (or `null` if not cached).
class LogoCacheService {
  const LogoCacheService();

  static const String _prefix = 'hesabi.logo.cache.';

  Future<void> save(String companyId, Uint8List bytes) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String encoded = base64Encode(bytes);
      await prefs.setString('$_prefix$companyId', encoded);
    } on Object catch (e) {
      AppLogger.warning('Failed to cache logo: $e');
    }
  }

  Future<Uint8List?> load(String companyId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? encoded = prefs.getString('$_prefix$companyId');
      if (encoded == null || encoded.isEmpty) return null;
      return base64Decode(encoded);
    } on Object catch (e) {
      AppLogger.warning('Failed to read cached logo: $e');
      return null;
    }
  }

  Future<void> clear(String companyId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$companyId');
    } on Object catch (e) {
      AppLogger.warning('Failed to clear cached logo: $e');
    }
  }
}
