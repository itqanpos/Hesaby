// lib/core/network/presentation/pending_operations_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../features/companies/presentation/providers/company_context_provider.dart';
import '../../../features/companies/presentation/providers/company_context_state.dart';
import '../../../shared/layouts/app_shell.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_empty.dart';
import '../network_status_provider.dart';
import '../operation_processor_providers.dart';
import '../operation_queue_providers.dart';
import '../pending_operation.dart';

/// Full-page view of every queued offline operation for the current
/// company.
///
/// Shows:
/// * A summary header (pending / failed counts).
/// * One tile per operation (type, created time, amount, status, error).
/// * Per-tile actions: retry (for pending / failed) and discard.
/// * A top-bar "send all now" action when the device is online.
/// * Pull-to-refresh triggers the same "send all" run.
class PendingOperationsPage extends ConsumerWidget {
  const PendingOperationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return AppShell(
        appBar: AppBar(title: const Text('العمليات المعلّقة')),
        body: const AppEmptyView(
          icon: Icons.business_outlined,
          title: 'لا توجد شركة',
          message: 'اختر شركة لعرض العمليات المعلّقة.',
        ),
      );
    }

    final List<PendingOperation> operations =
        ref.watch(companyOperationsProvider(companyId));
    final int pendingCount =
        ref.watch(pendingOperationCountProvider(companyId));
    final int failedCount =
        ref.watch(failedOperationCountProvider(companyId));
    final bool isOnline = ref.watch(isOnlineProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('العمليات المعلّقة'),
        actions: <Widget>[
          if (operations.isNotEmpty)
            IconButton(
              tooltip: isOnline
                  ? 'إرسال الكل الآن'
                  : 'لا يوجد اتصال بالإنترنت',
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: isOnline
                  ? () => _runAll(context, ref, companyId)
                  : null,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _onRefresh(ref, companyId),
        child: operations.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: operations.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return _SummaryHeader(
                      pending: pendingCount,
                      failed: failedCount,
                    );
                  }
                  return _OperationTile(operation: operations[index - 1]);
                },
              ),
      ),
    );
  }

  Future<void> _runAll(
    BuildContext context,
    WidgetRef ref,
    String companyId,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('جاري إرسال العمليات...')),
    );

    final int delivered = await runPendingOperations(
      ref,
      companyId: companyId,
    );

    if (!context.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            delivered > 0
                ? 'تم إرسال $delivered عملية.'
                : 'لم يتم إرسال أي عملية.',
          ),
        ),
      );
  }

  Future<void> _onRefresh(WidgetRef ref, String companyId) async {
    await runPendingOperations(ref, companyId: companyId);
  }
}

// ============================================================================
// Empty state
// ============================================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const AppEmptyView(
              icon: Icons.cloud_done_outlined,
              title: 'لا توجد عمليات معلّقة',
              message: 'كل شيء متزامن مع الخادم.',
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// Summary header
// ============================================================================

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.pending,
    required this.failed,
  });

  final int pending;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _cell(
                theme,
                label: 'قيد الانتظار',
                value: pending.toString(),
                color: scheme.primary,
              ),
            ),
            Container(
              width: 1,
              height: 36,
              color: scheme.outlineVariant,
            ),
            Expanded(
              child: _cell(
                theme,
                label: 'فشل',
                value: failed.toString(),
                color: failed > 0 ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    ThemeData theme, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// ============================================================================
// Operation tile
// ============================================================================

class _OperationTile extends ConsumerWidget {
  const _OperationTile({required this.operation});

  final PendingOperation operation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final (IconData icon, String label) = _typeInfo(operation.type);
    final Color accent = _statusAccent(scheme, operation.status);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _relativeTime(operation.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: operation.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle(operation),
              style: theme.textTheme.bodyMedium,
            ),
            if (operation.lastError != null && operation.isFailed) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                operation.lastError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                if (!operation.isProcessing)
                  TextButton.icon(
                    onPressed: () => _retry(context, ref),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('إعادة المحاولة'),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _discard(context, ref),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: scheme.error,
                  ),
                  label: Text(
                    'حذف',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool ok = await retryPendingOperation(
      ref,
      clientUuid: operation.clientUuid,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'تم إرسال العملية.' : 'تعذّر إرسال العملية. حاول مرة أخرى.',
        ),
      ),
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف العملية'),
        content: const Text(
          'سيتم حذف هذه العملية نهائيًا. لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'رجوع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'حذف',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await discardPendingOperation(
      ref,
      clientUuid: operation.clientUuid,
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('تم حذف العملية.')),
    );
  }
}

// ============================================================================
// Status chip
// ============================================================================

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PendingOperationStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final (String label, Color bg, Color fg) = switch (status) {
      PendingOperationStatus.pending => (
          'قيد الانتظار',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      PendingOperationStatus.processing => (
          'جاري الإرسال',
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      PendingOperationStatus.failed => (
          'فشل',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Helpers
// ============================================================================

/// Icon and Arabic label for a given operation type.
(IconData, String) _typeInfo(PendingOperationType type) {
  switch (type) {
    case PendingOperationType.sale:
      return (Icons.point_of_sale_outlined, 'فاتورة بيع');
    case PendingOperationType.customerPayment:
      return (Icons.payments_outlined, 'دفعة عميل');
    case PendingOperationType.supplierPayment:
      return (Icons.local_shipping_outlined, 'دفعة مورد');
    case PendingOperationType.expense:
      return (Icons.receipt_long_outlined, 'مصروف');
  }
}

Color _statusAccent(ColorScheme scheme, PendingOperationStatus status) {
  switch (status) {
    case PendingOperationStatus.pending:
      return scheme.primary;
    case PendingOperationStatus.processing:
      return scheme.tertiary;
    case PendingOperationStatus.failed:
      return scheme.error;
  }
}

/// Short description shown below the operation title.
String _subtitle(PendingOperation op) {
  if (op.type == PendingOperationType.sale) {
    final Object? itemsRaw = op.payload['items'];
    final int count = itemsRaw is List ? itemsRaw.length : 0;
    final double paid = _asDouble(op.payload['paid_amount']);
    return '$count صنف · مدفوع ${_money(paid)}';
  }
  final double amount = _asDouble(op.payload['amount']);
  return _money(amount);
}

/// Human-readable relative time for [dateTime].
String _relativeTime(DateTime dateTime) {
  final Duration diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60) return 'قبل لحظات';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
  if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
  final DateFormat fmt = DateFormat('yyyy-MM-dd HH:mm');
  return fmt.format(dateTime);
}

final NumberFormat _moneyFormat = NumberFormat.currency(
  locale: 'en_US',
  symbol: 'ج.م ',
  decimalDigits: 2,
);

String _money(double value) => _moneyFormat.format(value);

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
