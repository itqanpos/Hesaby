// lib/features/settings/data/services/company_logo_loader.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show NetworkAssetBundle;

import '../../../../core/utils/logger.dart';
import 'logo_cache_service.dart';

/// Loads the bytes of a company logo, preferring the local cache and
/// falling back to a network download.
///
/// Design notes:
/// * The cache is written right after an upload (see `_LogoSection`), so in
///   the common case the loader hits the cache and returns immediately.
/// * The network fallback exists for the edge cases: a user who signed in
///   on a new device, or a cache that was cleared by the OS.
/// * Any failure returns `null` — printing must never be blocked by a logo
///   download. Receipts simply print without the logo in that case.
class CompanyLogoLoader {
  const CompanyLogoLoader({
    this.cache = const LogoCacheService(),
  });

  final LogoCacheService cache;

  /// Returns the logo bytes for [companyId], or `null` when there is
  /// neither a cached copy nor a reachable [logoUrl].
  Future<Uint8List?> load({
    required String companyId,
    String? logoUrl,
  }) async {
    // 1) Cache hit → fastest path, no network.
    final Uint8List? cached = await cache.load(companyId);
    if (cached != null && cached.isNotEmpty) return cached;

    // 2) No URL → nothing to download.
    if (logoUrl == null || logoUrl.trim().isEmpty) return null;

    // 3) Network download (asset bundle handles http(s) transparently).
    final Uint8List? downloaded = await _download(logoUrl);
    if (downloaded != null && downloaded.isNotEmpty) {
      // Store for the next call, but never block on it.
      await cache.save(companyId, downloaded);
      return downloaded;
    }

    return null;
  }

  /// Fetches the logo URL. Never throws — failures are logged and
  /// swallowed so printing is not interrupted.
  Future<Uint8List?> _download(String url) async {
    try {
      final NetworkAssetBundle bundle =
          NetworkAssetBundle(Uri.parse(url));
      final ByteData data = await bundle.load(url);
      return data.buffer.asUint8List();
    } on Object catch (e) {
      AppLogger.warning('Logo download failed: $e');
      return null;
    }
  }
}
