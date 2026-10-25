// lib/shared/widgets/update_available_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/logger.dart';
import '../../features/admin/data/models/app_release.dart';
import '../../features/admin/presentation/providers/app_release_providers.dart';

/// رابط تحميل التحديث (GitHub Releases — أحدث إصدار دائماً).
const String _downloadUrl =
    'https://github.com/itqanpos/Hesaby/releases/latest';

/// مفتاح تخزين `build_number` الذي تم تجاهله في التطبيق المحلي.
const String _dismissedKey = 'hesabi.dismissed_update_build';

/// شريط يظهر أعلى الشاشة عند توفر إصدار أحدث من التطبيق.
///
/// **السلوك:**
/// * يقرأ الإصدار الحالي من `pubspec.yaml` (عبر `PackageInfo`).
/// * يجلب أحدث إصدار من جدول `app_releases` في Supabase.
/// * إذا كان `build_number` على الخادم أكبر من الإصدار الحالي → يظهر الشريط.
/// * زر "تحديث" يفتح رابط GitHub Releases في المتصفح.
/// * زر "✕" يحفظ `build_number` المُتجاهل في `SharedPreferences`،
///   فلا يظهر الشريط مرة أخرى حتى يصدر إصدار أحدث من نفس الرقم.
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

  Future<void> _openDownload() async {
    final Uri uri = Uri.parse(_downloadUrl);
    try {
      final bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        AppLogger.warning('Could not launch $_downloadUrl');
      }
    } catch (e) {
      AppLogger.warning('Launch error: $e');
    }
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
                ],
              ),
            ),
            TextButton(
              onPressed: _openDownload,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('تحديث'),
            ),
            if (!latest.isMandatory)
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
