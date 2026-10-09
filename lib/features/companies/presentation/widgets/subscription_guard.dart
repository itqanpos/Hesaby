// lib/features/companies/presentation/widgets/subscription_guard.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../providers/subscription_providers.dart';

/// Central choke point for **write-operation** gating.
///
/// The rule (Phase T-1 decisions): an account whose subscription is
/// **expired** or **cancelled** can still navigate, search, and read every
/// page — but must not be able to create, edit, delete, or record any new
/// data until it is renewed.
///
/// ## Usage
///
/// Call [ensureCanWrite] **before** the actual write action. It returns
/// `true` when the operation is allowed, and `false` (after showing an
/// informative dialog) when the account is blocked.
///
/// ```dart
/// Future<void> _onCheckout() async {
///   final bool ok = await SubscriptionGuard.ensureCanWrite(
///     context: context,
///     ref: ref,
///   );
///   if (!ok) return;
///   // … proceed with the actual write.
/// }
/// ```
///
/// When no company is selected (e.g. during onboarding, or in tests),
/// the guard returns `true` — it only cares about the subscription state
/// of the currently selected company.
abstract final class SubscriptionGuard {
  /// Returns `true` when the current company may perform write operations.
  ///
  /// Safe defaults:
  /// * No company selected         → `true` (no guard).
  /// * Unknown subscription state  → `true` (fail open at the UI layer;
  ///   the database RLS still protects the tenant's data).
  /// * `trial`, `active`           → `true`.
  /// * `expired`, `cancelled`      → `false` + shows a dialog.
  static Future<bool> ensureCanWrite({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final bool blocked = ref.read(isSubscriptionBlockedProvider);
    if (!blocked) return true;

    if (!context.mounted) return false;
    await _showBlockedDialog(context);
    return false;
  }

  /// Synchronous variant for cases where awaiting a dialog is not possible
  /// (e.g. inside a `Listenable`). It does **not** show the dialog; the
  /// caller is expected to surface the block through other UI (e.g. a
  /// SnackBar).
  static bool isWriteAllowed(WidgetRef ref) {
    return !ref.read(isSubscriptionBlockedProvider);
  }
}

// ============================================================================
// Blocked dialog
// ============================================================================

Future<void> _showBlockedDialog(BuildContext context) async {
  final bool? goToSubscription = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) =>
        const _BlockedDialogContent(),
  );

  if (goToSubscription == true && context.mounted) {
    await context.pushNamed(AppRouter.subscriptionName);
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
