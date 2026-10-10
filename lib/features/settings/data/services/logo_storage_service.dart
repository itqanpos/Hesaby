// lib/features/settings/data/services/logo_storage_service.dart

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart'
    show StorageException, Supabase, SupabaseClient;

import '../../../../core/utils/logger.dart';

/// Raised when a logo operation fails.
class LogoStorageException implements Exception {
  const LogoStorageException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'LogoStorageException: $message';
}

/// Handles upload / delete of company logos in the `company-logos` bucket.
///
/// The bucket is public-read so the URL can be embedded directly in
/// thermal/PDF documents without signed URLs. Write access is restricted
/// by RLS to owner / admin / manager, in the company's own folder.
class LogoStorageService {
  const LogoStorageService(this._client);

  final SupabaseClient? _client;

  static const String bucket = 'company-logos';

  /// Uploads [bytes] as the logo of [companyId], replacing any previous
  /// file. Returns the public URL (with a cache-busting timestamp).
  Future<String> upload({
    required String companyId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final SupabaseClient client = _requireClient();

    final String ext = _normalizeExtension(fileExtension);
    final String path = '$companyId/logo.$ext';

    try {
      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _mimeTypeFor(ext),
              cacheControl: '3600',
            ),
          );
    } on StorageException catch (e) {
      AppLogger.error('Logo upload failed', e);
      throw LogoStorageException(
        'تعذّر رفع الشعار إلى الخادم.',
        cause: e,
      );
    } on Object catch (e) {
      AppLogger.error('Logo upload unexpected error', e);
      throw LogoStorageException(
        'تعذر رفع الشعار. حاول مرة أخرى.',
        cause: e,
      );
    }

    final String base = client.storage.from(bucket).getPublicUrl(path);
    final int stamp = DateTime.now().millisecondsSinceEpoch;
    return '$base?t=$stamp';
  }

  /// Deletes the logo of [companyId]. Ignores errors when nothing exists.
  Future<void> delete(String companyId) async {
    final SupabaseClient client = _requireClient();

    // Try all known extensions — only one of them exists at a time.
    final List<String> paths = <String>[
      '$companyId/logo.png',
      '$companyId/logo.jpg',
      '$companyId/logo.jpeg',
      '$companyId/logo.webp',
    ];

    try {
      await client.storage.from(bucket).remove(paths);
    } on StorageException catch (e) {
      // Not fatal — the row is about to be cleared anyway.
      AppLogger.warning('Logo delete failed (non-fatal): $e');
    } on Object catch (e) {
      AppLogger.warning('Logo delete unexpected error (non-fatal): $e');
    }
  }

  static String _normalizeExtension(String ext) {
    final String cleaned = ext.toLowerCase().replaceAll('.', '');
    switch (cleaned) {
      case 'png':
        return 'png';
      case 'jpg':
      case 'jpeg':
        return 'jpg';
      case 'webp':
        return 'webp';
      default:
        return 'png';
    }
  }

  static String _mimeTypeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/png';
    }
  }

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const LogoStorageException(
        'Supabase client is not initialised.',
      );
    }
    return client;
  }
}

/// Bound to the active Supabase client.
final LogoStorageService logoStorageServiceFromSupabase =
    LogoStorageService(Supabase.instance.client);
