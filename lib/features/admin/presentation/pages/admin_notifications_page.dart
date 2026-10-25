// lib/features/admin/presentation/pages/admin_notifications_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';

// ============================================================================
// Provider
// ============================================================================

class AdminNotification {
  const AdminNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;

  factory AdminNotification.fromMap(Map<String, dynamic> map) {
    return AdminNotification(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      type: map['type'] as String? ?? 'system',
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

final notificationsProvider = FutureProvider.autoDispose<List<AdminNotification>>((ref) async {
  final client = Supabase.instance.client;
  final response = await client
      .from('admin_notifications')
      .select()
      .order('created_at', ascending: false)
      .limit(50);
  final List<dynamic> data = response as List<dynamic>;
  return data.whereType<Map<String, dynamic>>().map((e) => AdminNotification.fromMap(e)).toList();
});

// ============================================================================
// UI
// ============================================================================

class AdminNotificationsPage extends ConsumerWidget {
  const AdminNotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNotifs = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: asyncNotifs.when(
        loading: () => const AppLoader(),
        error: (Object e, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الإشعارات',
          message: 'حدث خطأ: $e',
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (List<AdminNotification> notifs) {
          if (notifs.isEmpty) {
            return const AppEmptyView(
              icon: Icons.notifications_none,
              title: 'لا توجد إشعارات',
              message: 'ستصلك التنبيهات هنا عند حدوث أي شيء مهم.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _NotificationTile(notification: notifs[i]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});
  final AdminNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color) = _getStyle(notification.type, scheme);

    return InkWell(
      onTap: () async {
        if (!notification.isRead) {
          await Supabase.instance.client.from('admin_notifications').update({'is_read': true}).eq('id', notification.id);
          ref.invalidate(notificationsProvider);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: notification.isRead ? scheme.surface : scheme.primaryContainer.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: notification.isRead ? scheme.outlineVariant : scheme.primary.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(notification.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(notification.message, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text(DateFormat('yyyy/MM/dd HH:mm').format(notification.createdAt), style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  static (IconData, Color) _getStyle(String type, ColorScheme scheme) {
    switch (type) {
      case 'support': return (Icons.support_agent, const Color(0xFF0288D1));
      case 'subscription': return (Icons.workspace_premium, const Color(0xFFEF6C00));
      case 'company': return (Icons.business, const Color(0xFF6A1B9A));
      default: return (Icons.info, scheme.primary);
    }
  }
}
