// lib/shared/widgets/sync_status_indicator.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/network/network_status_provider.dart';
import '../../core/network/operation_queue.dart';
import '../../core/network/operation_queue_providers.dart';
import '../../core/network/operation_trigger.dart';
import '../../core/network/pending_operation.dart';
import '../../features/companies/presentation/providers/company_context_provider.dart';

/// A smart banner that adapts its message and action based on the state:
///
/// * **Online + no pending** → hidden (nothing to show).
/// * **Online + pending** → blue "جاري مزامنة N عملية..." with spinner.
/// * **Online + failed** → red "N عملية فشلت في المزامنة" (tap → sync center).
/// * **Offline + pending** → orange "غير متصل - N معلقة" (tap → sync center).
/// * **Offline + no pending** → grey "غير متصل بالإنترنت" (subtle).
///
/// For a **field sales rep**, this is critical: the banner always tells
/// them exactly what's going on, and tapping it reveals a full sync center.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? companyId = ref.watch(
      companyContextProvider.select((s) => s.currentCompany?.id),
    );
    if (companyId == null) return const SizedBox.shrink();

    final bool isOnline = ref.watch(isOnlineProvider);
    final int pending = ref.watch(pendingOperationCountProvider(companyId));
    final int failed = ref.watch(failedOperationCountProvider(companyId));

    // Everything is fine: online + no pending + no failures
    if (isOnline && pending == 0 && failed == 0) {
      return const SizedBox.shrink();
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;

    // 1. Failed operations — highest priority
    if (failed > 0) {
      return _SyncBanner(
        icon: Icons.error_outline,
        background: scheme.error,
        foreground: scheme.onError,
        title: '$failed عملية فشلت في المزامنة',
        subtitle: pending > 0
            ? 'و $pending عملية معلقة · اضغط للمراجعة'
            : 'اضغط للمراجعة وإعادة المحاولة',
        onTap: () => _openSyncCenter(context),
      );
    }

    // 2. Online + pending → syncing
    if (isOnline && pending > 0) {
      return _SyncBanner(
        icon: Icons.sync,
        background: const Color(0xFF0288D1),
        foreground: Colors.white,
        title: 'جاري مزامنة $pending عملية...',
        subtitle: 'لا تغلق التطبيق',
        showSpinner: true,
      );
    }

    // 3. Offline + pending
    if (!isOnline && pending > 0) {
      return _SyncBanner(
        icon: Icons.cloud_off_outlined,
        background: const Color(0xFFEF6C00),
        foreground: Colors.white,
        title: 'غير متصل — $pending عملية معلقة',
        subtitle: 'ستتم المزامنة تلقائياً عند عودة الإنترنت',
        onTap: () => _openSyncCenter(context),
      );
    }

    // 4. Offline + no pending → subtle
    return _SyncBanner(
      icon: Icons.cloud_off_outlined,
      background: scheme.surfaceContainerHighest,
      foreground: scheme.onSurfaceVariant,
      title: 'غير متصل بالإنترنت',
      subtitle: 'يمكنك البيع — ستُحفظ العمليات محلياً',
    );
  }

  void _openSyncCenter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _SyncCenterSheet(),
    );
  }
}

// ============================================================================
// Banner widget (shared)
// ============================================================================

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.showSpinner = false,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          showSpinner
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.85),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 8),
            Icon(Icons.chevron_left, color: foreground, size: 20),
          ],
        ],
      ),
    );

    return Material(
      color: background,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

// ============================================================================
// Sync Center (bottom sheet)
// ============================================================================

class _SyncCenterSheet extends ConsumerWidget {
  const _SyncCenterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? companyId = ref.watch(
      companyContextProvider.select((s) => s.currentCompany?.id),
    );

    if (companyId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final AsyncValue<OperationQueue> queueAsync =
        ref.watch(operationQueueProvider);
    final bool isOnline = ref.watch(isOnlineProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (BuildContext context, ScrollController scrollController) {
        return queueAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace _) =>
              Center(child: Text('خطأ: $e')),
          data: (OperationQueue queue) {
            final List<PendingOperation> all = queue.forCompany(companyId);
            final List<PendingOperation> pending = all
                .where((PendingOperation op) => op.isPending)
                .toList(growable: false);
            final List<PendingOperation> failed = all
                .where((PendingOperation op) => op.isFailed)
                .toList(growable: false);

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: <Widget>[
                // Header
                Row(
                  children: <Widget>[
                    Icon(Icons.sync, color: scheme.primary, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'مركز المزامنة',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isOnline
                      ? 'أنت متصل. اضغط "مزامنة الآن" لإرسال العمليات.'
                      : 'أنت غير متصل. ستتم المزامنة تلقائياً عند عودة الإنترنت.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // Summary cards
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.schedule,
                        color: const Color(0xFFEF6C00),
                        label: 'معلقة',
                        value: pending.length.toString(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.error_outline,
                        color: scheme.error,
                        label: 'فشلت',
                        value: failed.length.toString(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Sync now button
                if (isOnline && pending.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.sync),
                      label: const Text('مزامنة الآن'),
                      onPressed: () {
                        ref
                            .read(operationTriggerProvider)
                            .triggerIfPossible();
                      },
                    ),
                  ),
                if (!isOnline)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.cloud_off_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لا يمكن المزامنة الآن. سيتم المحاولة تلقائياً عند توفر الإنترنت.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Failed section (priority)
                if (failed.isNotEmpty) ...<Widget>[
                  _SectionTitle(
                    title: 'عمليات فشلت (${failed.length})',
                    color: scheme.error,
                  ),
                  const SizedBox(height: 8),
                  for (final PendingOperation op in failed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OperationCard(
                        operation: op,
                        isFailed: true,
                        onRetry: isOnline
                            ? () async {
                                await queue.update(
                                  op.copyWith(
                                    status: PendingOperationStatus.pending,
                                    attemptCount: 0,
                                    lastError: null,
                                  ),
                                );
                                await ref
                                    .read(operationTriggerProvider)
                                    .triggerIfPossible();
                              }
                            : null,
                      ),
                    ),
                  const SizedBox(height: 16),
                ],

                // Pending section
                if (pending.isNotEmpty) ...<Widget>[
                  _SectionTitle(
                    title: 'قيد الانتظار (${pending.length})',
                    color: const Color(0xFFEF6C00),
                  ),
                  const SizedBox(height: 8),
                  for (final PendingOperation op in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OperationCard(
                        operation: op,
                        isFailed: false,
                        onRetry: null,
                      ),
                    ),
                ],

                if (pending.isEmpty && failed.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: <Widget>[
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: const Color(0xFF0F7B6C)
                              .withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'كل شيء متزامن',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// Small widgets
// ============================================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.color});
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.operation,
    required this.isFailed,
    this.onRetry,
  });

  final PendingOperation operation;
  final bool isFailed;
  final Future<void> Function()? onRetry;

  String get _typeLabel => switch (operation.type) {
        PendingOperationType.sale => 'فاتورة بيع',
        PendingOperationType.customerPayment => 'دفعة عميل',
        PendingOperationType.supplierPayment => 'دفعة مورد',
        PendingOperationType.expense => 'مصروف',
      };

  IconData get _typeIcon => switch (operation.type) {
        PendingOperationType.sale => Icons.receipt_long_outlined,
        PendingOperationType.customerPayment => Icons.payments_outlined,
        PendingOperationType.supplierPayment =>
          Icons.local_shipping_outlined,
        PendingOperationType.expense => Icons.money_off,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String dateStr =
        DateFormat('yyyy/MM/dd HH:mm').format(operation.createdAt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFailed
              ? scheme.error.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _typeIcon,
                color: isFailed ? scheme.error : scheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _typeLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                dateStr,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (isFailed && operation.lastError != null) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_outlined,
                    color: scheme.onErrorContainer,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      operation.lastError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isFailed && onRetry != null) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة المحاولة'),
                onPressed: () async {
                  await onRetry!();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
