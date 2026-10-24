// lib/features/admin/presentation/pages/tabs/admin_storage_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';

// ============================================================================
// Models
// ============================================================================

class DatabaseUsage {
  const DatabaseUsage({
    required this.dbSizePretty,
    required this.dbSizeBytes,
    required this.limitMb,
    required this.usagePercent,
  });

  final String dbSizePretty;
  final int dbSizeBytes;
  final int limitMb;
  final double usagePercent;

  factory DatabaseUsage.fromJson(Map<String, dynamic> json) {
    return DatabaseUsage(
      dbSizePretty: json['db_size_pretty'] as String? ?? '0 MB',
      dbSizeBytes: (json['db_size_bytes'] as num?)?.toInt() ?? 0,
      limitMb: (json['limit_mb'] as num?)?.toInt() ?? 500,
      usagePercent: (json['usage_percent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ============================================================================
// Provider
// ============================================================================

final dbUsageProvider = FutureProvider.autoDispose<DatabaseUsage>((ref) async {
  final client = Supabase.instance.client;
  final response = await client.rpc('get_database_usage');
  
  if (response is! Map) {
    throw Exception('Invalid response from database usage RPC');
  }
  return DatabaseUsage.fromJson(Map<String, dynamic>.from(response));
});

// ============================================================================
// UI
// ============================================================================

class AdminStorageTab extends ConsumerWidget {
  const AdminStorageTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncUsage = ref.watch(dbUsageProvider);

    return asyncUsage.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل بيانات المساحة',
        message: 'حدث خطأ: $error',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(dbUsageProvider),
      ),
      data: (DatabaseUsage data) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        
        // تحديد اللون بناءً على النسبة
        final Color statusColor = data.usagePercent >= 85 
            ? const Color(0xFFC62828) // أحمر
            : data.usagePercent >= 70 
                ? const Color(0xFFEF6C00) // برتقالي
                : const Color(0xFF0F7B6C); // أخضر

        return RefreshIndicator(
          onRefresh: () => ref.refresh(dbUsageProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              Text(
                'استهلاك قاعدة البيانات',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // شريط التقدم الدائري
              Center(
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CircularProgressIndicator(
                        value: data.usagePercent / 100,
                        strokeWidth: 16,
                        backgroundColor: scheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                        strokeCap: StrokeCap.round,
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '${data.usagePercent.toStringAsFixed(1)}%',
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                            Text(
                              'مستخدمة',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // تفاصيل الاستهلاك
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: <Widget>[
                    _InfoRow(
                      label: 'المساحة المستخدمة',
                      value: data.dbSizePretty,
                      icon: Icons.storage,
                      color: statusColor,
                    ),
                    const Divider(height: 24),
                    _InfoRow(
                      label: 'الحد الأقصى للخطة',
                      value: '${data.limitMb} MB',
                      icon: Icons.data_usage,
                      color: scheme.primary,
                    ),
                    const Divider(height: 24),
                    _InfoRow(
                      label: 'المساحة المتبقية',
                      value: '${data.limitMb - (data.dbSizeBytes / 1024 / 1024).round()} MB',
                      icon: Icons.check_circle_outline,
                      color: const Color(0xFF0F7B6C),
                    ),
                  ],
                ),
              ),

              // تنبيهات
              if (data.usagePercent >= 70) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.warning_amber_rounded, color: statusColor, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          data.usagePercent >= 85
                              ? 'تحذير حرج: المساحة أوشكت على الامتلاء! يجب ترقية الخطة أو حذف بيانات قديمة فوراً.'
                              : 'تنبيه: المساحة تتزايد. ننصح بمراقبة الاستهلاك أو التفكير في ترقية الخطة قريباً.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
