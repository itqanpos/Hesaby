// lib/features/admin/data/models/app_release.dart

/// يمثل إصداراً من التطبيق تم نشره.
///
/// يُقرأ من جدول `app_releases` في قاعدة البيانات، ويستخدمه شريط
/// التحديث (`UpdateAvailableBanner`) لمعرفة متى يجب تنبيه المستخدم.
class AppRelease {
  const AppRelease({
    required this.id,
    required this.versionName,
    required this.buildNumber,
    required this.isMandatory,
    required this.createdAt,
    this.releaseNotes,
  });

  final String id;

  /// الاسم الظاهر للإصدار، مثال: "1.0.5".
  final String versionName;

  /// رقم البناء الفريد، يجب أن يزداد مع كل إصدار، مثال: 6, 7, 8.
  /// المقارنة بين إصدار المستخدم والـ build_number هي الأساس.
  final int buildNumber;

  /// هل هذا الإصدار إجباري؟ (للتنبيهات الحرجة)
  final bool isMandatory;

  /// ملاحظات التحديث (Release Notes).
  final String? releaseNotes;

  final DateTime createdAt;

  factory AppRelease.fromMap(Map<String, dynamic> map) {
    return AppRelease(
      id: map['id'] as String,
      versionName: map['version_name'] as String? ?? '0.0.0',
      buildNumber: (map['build_number'] as num?)?.toInt() ?? 0,
      isMandatory: map['is_mandatory'] as bool? ?? false,
      releaseNotes: map['release_notes'] as String?,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }

  @override
  String toString() =>
      'AppRelease(version: $versionName, build: $buildNumber, mandatory: $isMandatory)';
}
