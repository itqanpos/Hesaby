// lib/features/admin/presentation/providers/app_release_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/app_release.dart';

// ============================================================================
// Current app info (from pubspec.yaml at build time)
// ============================================================================

/// معلومات إصدار التطبيق الحالي (تُقرأ من pubspec.yaml).
///
/// يُستخدم `buildNumber` للمقارنة مع أحدث إصدار على الخادم.
final currentAppInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

// ============================================================================
// Latest release from database
// ============================================================================

/// أحدث إصدار مسجل في جدول `app_releases`.
///
/// إذا كان الجدول فارغاً، يُرجع `null`.
final latestReleaseProvider = FutureProvider<AppRelease?>((ref) async {
  try {
    final client = Supabase.instance.client;
    final response = await client
        .from('app_releases')
        .select()
        .order('build_number', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return AppRelease.fromMap(response);
  } catch (_) {
    // إذا فشل الاتصال أو لم يكن الجدول موجوداً، نتعامل معه كـ "لا يوجد تحديث"
    return null;
  }
});

// ============================================================================
// Update availability (computed)
// ============================================================================

/// نتيجة المقارنة بين الإصدار الحالي وأحدث إصدار على الخادم.
class UpdateInfo {
  const UpdateInfo({
    required this.isAvailable,
    this.latest,
    this.currentBuildNumber,
  });

  /// هل هناك إصدار أحدث من التطبيق الحالي؟
  final bool isAvailable;

  /// أحدث إصدار على الخادم (إن وُجد).
  final AppRelease? latest;

  /// رقم البناء الحالي للتطبيق (من pubspec.yaml).
  final int? currentBuildNumber;

  const UpdateInfo.noUpdate()
      : isAvailable = false,
        latest = null,
        currentBuildNumber = null;
}

/// يُرجع معلومات التحديث إذا كان هناك إصدار أحدث متاح.
final updateAvailableProvider = FutureProvider<UpdateInfo>((ref) async {
  try {
    final PackageInfo current =
        await ref.watch(currentAppInfoProvider.future);
    final AppRelease? latest =
        await ref.watch(latestReleaseProvider.future);

    if (latest == null) {
      return const UpdateInfo.noUpdate();
    }

    final int currentBuild = int.tryParse(current.buildNumber) ?? 0;

    return UpdateInfo(
      isAvailable: latest.buildNumber > currentBuild,
      latest: latest,
      currentBuildNumber: currentBuild,
    );
  } catch (_) {
    return const UpdateInfo.noUpdate();
  }
});
