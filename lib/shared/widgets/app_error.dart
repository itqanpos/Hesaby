// lib/shared/widgets/app_error.dart
import 'package:flutter/material.dart';

import 'app_button.dart';

/// Standard error state used across HESABI.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.error_outline,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final String? title;
  final IconData icon;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? titleText = title;
    final String? actionLabel = retryLabel;
    final VoidCallback? retry = onRetry;
    final bool showRetry = retry != null && actionLabel != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            if (titleText != null)
              Text(
                titleText,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            if (titleText != null) const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (showRetry) const SizedBox(height: 24),
            if (showRetry)
              AppButton(
                label: actionLabel,
                icon: Icons.refresh,
                onPressed: retry,
              ),
          ],
        ),
      ),
    );
  }
}
