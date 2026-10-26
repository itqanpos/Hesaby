// lib/shared/widgets/update_available_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/logger.dart';
import '../../features/admin/data/models/app_release.dart';
import '../../features/admin/presentation/providers/app_release_providers.dart';

/// مفتاح تخزين `build_number` الذي تم تجاهله في التطبيق المحلي.
const String _dismissedKey = 'hesabi.dismissed_update_build';

/// شريط يظهر أعلى الشاشة عند توفر إصدار أحدث من التطبيق.
///
/// **السلوك (محدّث — الخيار أ):**
/// * يقرأ الإصدار الحالي من `pubspec.yaml` (عبر `PackageInfo`).
/// * يجلب أحدث إصدار من جدول `app_releases` في Supabase.
/// * إذا كان `build_number` على الخادم أكبر من الإصدار الحالي → يظهر الشريط.
/// * زر "تحديث" يفتح **`latest.downloadUrl`** (رابط مخصص يُدار من لوحة
///   الأدمن)، **وليس** رابط GitHub الثابت كما كان سابقًا.
/// * إذا كان `downloadUrl` فارغًا: يظهر الشريط برسالة "تواصل مع الدعم"
///   بدون زر "تحديث"، ويُسمح بالإغلاق دائمًا (حتى لو كان الإصدار إجباريًا،
///   لأن المستخدم لا يملك طريقة للتحديث من داخل التطبيق).
/// * زر "✕" يحفظ `build_number` المُتجاهل في `SharedPreferences`.
class UpdateAvailableBanner extends ConsumerStatefulWidget {
  const UpdateAvailableBanner({super.key});

  @override
  ConsumerState<UpdateAvailableBanner> createState() =>
      _UpdateAvailableBannerState();
}

class _UpdateAvailableBannerState extends ConsumerState<UpdateAvailableBanner> {
  bool _loadedPrefs = false;
  bool _manuallyDismissed = false;
  int? _dismissedBuild;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _dismissedBuild = prefs.getInt(_dismissedKey);
        _loadedPrefs = true;
      });
    } catch (e) {
      AppLogger.warning('Failed to load dismissed update: $e');
      if (mounted) setState(() => _loadedPrefs = true);
    }
  }

  Future<void> _dismiss(int buildNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_dismissedKey, buildNumber);
    } catch (e) {
      AppLogger.warning('Failed to save dismissed update: $e');
    }
    if (mounted) setState(() => _manuallyDismissed = true);
  }

  Future<void> _openDownload(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _showSnack('رابط التحميل غير صالح. يرجى التواصل مع الدعم.');
      return;
    }
    try {
      final bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        _showSnack('تعذّر فتح رابط التحميل.');
      }
    } catch (e) {
      AppLogger.warning('Launch error: $e');
      _showSnack('تعذّر فتح رابط التحميل.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loadedPrefs || _manuallyDismissed) return const SizedBox.shrink();

    final AsyncValue<UpdateInfo> async = ref.watch(updateAvailableProvider);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (UpdateInfo info) {
        if (!info.isAvailable || info.latest == null) {
          return const SizedBox.shrink();
        }

        // إذا تجاهل المستخدم هذا الـ build_number أو أحدث، لا نعرضه.
        if (_dismissedBuild != null &&
            info.latest!.buildNumber <= _dismissedBuild!) {
          return const SizedBox.shrink();
        }

        return _buildBanner(context, info.latest!);
      },
    );
  }

  Widget _buildBanner(BuildContext context, AppRelease latest) {
    final ThemeData theme = Theme.of(context);
    final bool hasUrl = latest.hasDownloadUrl;

    // الإغلاق مسموح إذا:
    //   - الإصدار غير إجباري، أو
    //   - الإصدار إجباري لكن لا يوجد رابط تحميل (حماية من قفل المستخدم).
    final bool canDismiss = !latest.isMandatory || !hasUrl;

    return Material(
      color: latest.isMandatory
          ? const Color(0xFFC62828)
          : const Color(0xFF0288D1),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.system_update, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    latest.isMandatory
                        ? 'تحديث إجباري متوفر: v${latest.versionName}'
                        : 'تحديث جديد متوفر: v${latest.versionName}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (latest.releaseNotes != null &&
                      latest.releaseNotes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        latest.releaseNotes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (!hasUrl)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'تواصل مع الدعم للحصول على التحديث.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (hasUrl)
              TextButton(
                onPressed: () => _openDownload(latest.downloadUrl!),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('تحديث'),
              ),
            if (canDismiss)
              IconButton(
                onPressed: () => _dismiss(latest.buildNumber),
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'تجاهل هذا الإصدار',
              ),
          ],
        ),
      ),
    );
  }
}
