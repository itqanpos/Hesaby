// lib/features/reports/presentation/widgets/report_page_scaffold.dart

import 'package:flutter/material.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../domain/entities/report_period.dart';
import 'report_period_selector.dart';

/// Shared scaffold for every report page.
///
/// Provides:
/// * a title bar,
/// * the current period as a tappable pill (opens the period selector),
/// * a consistent loading / error / body layout.
class ReportPageScaffold extends StatelessWidget {
  const ReportPageScaffold({
    super.key,
    required this.title,
    required this.period,
    required this.onPeriodChanged,
    required this.body,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.trailing,
  });

  final String title;
  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onPeriodChanged;

  /// The report body, shown when [isLoading] is false and [errorMessage] is
  /// null.
  final Widget body;

  final bool isLoading;

  /// When non-null, an error view replaces the body.
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Optional trailing widget (e.g. an export button).
  final Widget? trailing;

  Future<void> _openPeriodSelector(BuildContext context) async {
    final ReportPeriod? result = await showReportPeriodSelector(
      context: context,
      current: period,
    );
    if (result == null) {
      return;
    }
    onPeriodChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          if (trailing != null) trailing!,
          Center(
            child: ReportPeriodButton(
              period: period,
              onPressed: () => _openPeriodSelector(context),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return _ReportErrorView(
        message: errorMessage!,
        onRetry: onRetry,
      );
    }

    return body;
  }
}

class _ReportErrorView extends StatelessWidget {
  const _ReportErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, color: scheme.error, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
