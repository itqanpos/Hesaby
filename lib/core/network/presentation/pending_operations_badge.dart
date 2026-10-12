// lib/core/network/presentation/pending_operations_badge.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/companies/presentation/providers/company_context_provider.dart';
import '../../../features/companies/presentation/providers/company_context_state.dart';
import '../operation_queue_providers.dart';
import 'pending_operations_page.dart';

/// Small AppBar action that shows how many offline operations are queued
/// for the current company.
///
/// * **No operations** → renders nothing (zero height).
/// * **Pending only** → outlined cloud icon with a small count badge.
/// * **Failed present** → error-coloured cloud icon (draws attention).
///
/// Tapping the icon opens [PendingOperationsPage].
class PendingOperationsBadge extends ConsumerWidget {
  const PendingOperationsBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const SizedBox.shrink();
    }

    final int pending =
        ref.watch(pendingOperationCountProvider(companyId));
    final int failed =
        ref.watch(failedOperationCountProvider(companyId));
    final int total = pending + failed;

    if (total == 0) {
      return const SizedBox.shrink();
    }

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool hasFailures = failed > 0;

    return IconButton(
      tooltip: hasFailures
          ? 'فشل $failed — اضغط للتفاصيل'
          : '$pending عملية قيد الإرسال',
      icon: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Icon(
            hasFailures
                ? Icons.cloud_off_outlined
                : Icons.cloud_upload_outlined,
            color: hasFailures ? scheme.error : null,
          ),
          PositionedDirectional(
            end: -6,
            top: -6,
            child: _Badge(
              count: total,
              background: hasFailures ? scheme.error : scheme.primary,
              foreground: hasFailures
                  ? scheme.onError
                  : scheme.onPrimary,
            ),
          ),
        ],
      ),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PendingOperationsPage(),
          ),
        );
      },
    );
  }
}

/// Small circular counter badge.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.count,
    required this.background,
    required this.foreground,
  });

  final int count;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : '$count';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
