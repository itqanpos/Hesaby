// lib/features/admin/presentation/pages/tabs/admin_audit_log_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../shared/widgets/app_empty.dart';
import '../../../../../shared/widgets/app_error.dart';
import '../../../../../shared/widgets/app_loader.dart';

// ============================================================================
// Models
// ============================================================================

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.actorEmail,
    required this.action,
    required this.entityType,
    required this.entityLabel,
    required this.reason,
    required this.createdAt,
    this.metadata,
  });

  final String id;
  final String actorEmail;
  final String action;
  final String entityType;
  final String? entityLabel;
  final String? reason;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] as String,
      actorEmail: map['actor_email'] as String? ?? 'غير معروف',
      action: map['action'] as String? ?? 'حركة غير مسماة',
      entityType: map['entity_type'] as String? ?? '',
      entityLabel: map['entity_label'] as String?,
      reason: map['reason'] as String?,
      createdAt: _parseDate(map['created_at']),
      metadata: map['metadata'] as Map<String, dynamic>?,
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

final auditLogsProvider = FutureProvider.autoDispose<List<AuditLogEntry>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('audit_logs')
      .select()
      .order('created_at', ascending: false)
      .limit(100);

  final List<dynamic> data = response as List<dynamic>;
  return data
      .map((e) => AuditLogEntry.fromMap(e as Map<String, dynamic>))
      .toList();
});

// ============================================================================
// UI
// ============================================================================

class AdminAuditLogTab extends ConsumerWidget {
  const AdminAuditLogTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLogs = ref.watch(auditLogsProvider);

    return asyncLogs.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل السجل',
        message: 'حدث خطأ أثناء جلب سجل التدقيق: $error',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(auditLogsProvider),
      ),
      data: (List<AuditLogEntry> logs) {
        if (logs.isEmpty) {
          return const AppEmptyView(
            icon: Icons.history,
            title: 'لا توجد سجلات',
            message: 'لم يتم تسجيل أي حركات إدارية حتى الآن.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            return _AuditLogCard(entry: logs[index]);
          },
        );
      },
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({required this.entry});
  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    
    final (IconData icon, Color color) = _getActionStyle(entry.action, scheme);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.action,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                    if (entry.entityLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.entityLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'بواسطة: ${entry.actorEmail}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textDirection: TextDirection.ltr,
                ),
                if (entry.reason != null && entry.reason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'السبب: ${entry.reason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  DateFormat('yyyy/MM/dd HH:mm').format(entry.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color) _getActionStyle(String action, ColorScheme scheme) {
    if (action.contains('إيقاف')) return (Icons.block, scheme.error);
    if (action.contains('تفعيل')) return (Icons.check_circle_outline, const Color(0xFF0F7B6C));
    if (action.contains('أدمن') || action.contains('صلاحية')) return (Icons.security, const Color(0xFF6A1B9A));
    if (action.contains('اشتراك')) return (Icons.workspace_premium, const Color(0xFFEF6C00));
    return (Icons.info_outline, scheme.primary);
  }
}
