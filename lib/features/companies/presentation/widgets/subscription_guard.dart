// lib/features/companies/presentation/widgets/subscription_guard.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../providers/company_status_provider.dart';
import '../providers/subscription_providers.dart';

/// Central choke point for **write-operation** gating.
abstract final class SubscriptionGuard {
  static Future<bool> ensureCanWrite({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    // 1. فحص الإيقاف الإداري (من لوحة تحكم المنصة) أو انتهاء التاريخ
    if (!ref.read(companyCanWriteProvider)) {
      final CompanyStatusInfo info = ref.read(companyStatusProvider);
      
      if (!context.mounted) return false;
      
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              info.isSuspended ? Icons.block : Icons.hourglass_bottom,
              color: Theme.of(context).colorScheme.onErrorContainer,
              size: 28,
            ),
          ),
          title: Text(
            info.isSuspended ? 'الحساب موقوف' : 'انتهت صلاحية الاشتراك',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                info.reason?.isNotEmpty == true
                    ? info.reason!
                    : 'لا يمكن إجراء عمليات جديدة في الوقت الحالي.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'يمكنك تصفح البيانات والتقارير كالمعتاد، لكن العمليات الجديدة '
                '(بيع، شراء، تعديل) معطلة حتى يتم التجديد أو إعادة التفعيل.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return false;
    }

    // 2. الفحص الأصلي للاشتراك
    final bool blocked = ref.read(isSubscriptionBlockedProvider);
    if (!blocked) return true;

    if (!context.mounted) return false;
    await _showBlockedDialog(context);
    return false;
  }

  static bool isWriteAllowed(WidgetRef ref) {
    if (!ref.read(companyCanWriteProvider)) return false;
    return !ref.read(isSubscriptionBlockedProvider);
  }
}

Future<void> _showBlockedDialog(BuildContext context) async {
  final bool? goToSubscription = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => const _BlockedDialogContent(),
  );

  if (goToSubscription == true && context.mounted) {
    await context.pushNamed(AppRouter.accountName);
  }
}

class _BlockedDialogContent extends StatelessWidget {
  const _BlockedDialogContent();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.lock_outline,
          color: scheme.onErrorContainer,
          size: 28,
        ),
      ),
      title: const Text('الحساب للقراءة فقط'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'انتهى اشتراك شركتك، ولا يمكن حاليًا إجراء عمليات جديدة.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'يمكنك تصفح البيانات والتقارير كالمعتاد. لتجديد الاشتراك '
            'واستعادة كل الميزات، انتقل إلى صفحة الاشتراك.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('لاحقًا'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.workspace_premium_outlined, size: 18),
          label: const Text('تجديد الآن'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
