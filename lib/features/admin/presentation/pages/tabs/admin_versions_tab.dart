// lib/features/admin/presentation/pages/tabs/admin_versions_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';

// ============================================================================
// Models
// ============================================================================

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
  final String versionName;
  final int buildNumber;
  final bool isMandatory;
  final DateTime createdAt;
  final String? releaseNotes;

  factory AppRelease.fromMap(Map<String, dynamic> map) {
    return AppRelease(
      id: map['id'] as String,
      versionName: map['version_name'] as String,
      buildNumber: (map['build_number'] as num).toInt(),
      isMandatory: map['is_mandatory'] as bool? ?? false,
      createdAt: _parseDate(map['created_at']),
      releaseNotes: map['release_notes'] as String?,
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) {
      DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
      try {
        String normalized = value.trim();
        if (normalized.contains(' ')) normalized = normalized.replaceFirst(' ', 'T');
        if (normalized.endsWith('+00')) normalized = normalized.replaceAll('+00', 'Z');
        parsed = DateTime.tryParse(normalized);
        if (parsed != null) return parsed.toLocal();
      } catch (_) {}
    }
    return DateTime.now();
  }
}

// ============================================================================
// Provider
// ============================================================================

final appReleasesProvider = FutureProvider.autoDispose<List<AppRelease>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('app_releases')
      .select()
      .order('build_number', ascending: false);

  final List<dynamic> data = response as List<dynamic>;
  return data.whereType<Map<String, dynamic>>().map((e) => AppRelease.fromMap(e)).toList();
});

// ============================================================================
// UI
// ============================================================================

class AdminVersionsTab extends ConsumerWidget {
  const AdminVersionsTab({super.key});

  Future<void> _showAddReleaseDialog(BuildContext context, WidgetRef ref) async {
    final bool? added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AddReleaseDialog(),
    );
    if (added == true) {
      ref.invalidate(appReleasesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الإصدار الجديد بنجاح.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReleases = ref.watch(appReleasesProvider);

    return asyncReleases.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل الإصدارات',
        message: 'حدث خطأ: $error',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(appReleasesProvider),
      ),
      data: (List<AppRelease> releases) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppButton(
                label: 'تسجيل إصدار جديد (Release)',
                icon: Icons.new_releases,
                onPressed: () => _showAddReleaseDialog(context, ref),
              ),
            ),
            Expanded(
              child: releases.isEmpty
                  ? const AppEmptyView(
                      icon: Icons.system_update,
                      title: 'لا توجد إصدارات',
                      message: 'قم بتسجيل أول إصدار لك لتتمكن من تتبع التحديثات.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: releases.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _ReleaseCard(release: releases[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release});
  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: release.isMandatory ? scheme.error : scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: release.isMandatory ? scheme.errorContainer : scheme.primaryContainer,
                child: Icon(Icons.rocket_launch, color: release.isMandatory ? scheme.onErrorContainer : scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'الإصدار ${release.versionName}',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(بناء ${release.buildNumber})',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('yyyy/MM/dd HH:mm').format(release.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
              if (release.isMandatory)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: scheme.error, borderRadius: BorderRadius.circular(6)),
                  child: const Text('إجباري', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          if (release.releaseNotes != null && release.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('ملاحظات التحديث:', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(release.releaseNotes!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ]
        ],
      ),
    );
  }
}

// ============================================================================
// Add Release Dialog
// ============================================================================

class _AddReleaseDialog extends ConsumerStatefulWidget {
  const _AddReleaseDialog();
  @override
  ConsumerState<_AddReleaseDialog> createState() => _AddReleaseDialogState();
}

class _AddReleaseDialogState extends ConsumerState<_AddReleaseDialog> {
  final _versionCtrl = TextEditingController();
  final _buildCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isMandatory = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _versionCtrl.dispose(); _buildCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final version = _versionCtrl.text.trim();
    final buildNum = int.tryParse(_buildCtrl.text.trim()) ?? 0;

    if (version.isEmpty || buildNum <= 0) {
      setState(() => _error = 'الرجاء إدخال رقم إصدار وبناء صحيح');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final client = Supabase.instance.client;
      await client.from('app_releases').insert({
        'version_name': version,
        'build_number': buildNum,
        'release_notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'is_mandatory': _isMandatory,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _error = 'خطأ: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تسجيل إصدار جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(controller: _versionCtrl, label: 'رقم الإصدار', hint: 'مثال: 1.0.5'),
            const SizedBox(height: 12),
            AppTextField(
              controller: _buildCtrl,
              label: 'رقم البناء (Build Number)',
              hint: 'مثال: 6',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            AppTextField(controller: _notesCtrl, label: 'ملاحظات التحديث (Release Notes)', maxLines: 3),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('تحديث إجباري'),
              subtitle: const Text('لن يتمكن المستخدم من استخدام التطبيق إلا بعد التحديث'),
              value: _isMandatory,
              onChanged: (v) => setState(() => _isMandatory = v),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Theme.of(context).colorScheme.error,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        AppButton(label: 'حفظ', isLoading: _isLoading, onPressed: _isLoading ? null : _submit),
      ],
    );
  }
}
