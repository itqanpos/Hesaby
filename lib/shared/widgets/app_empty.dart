// lib/shared/widgets/app_empty.dart
import 'package:flutter/material.dart';

/// Standard empty state used across HESABI.
class AppEmptyView extends StatelessWidget {
  const AppEmptyView({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String message;
  final String? title;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? titleText = title;
    final Widget? actionWidget = action;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: scheme.outline),
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
            if (actionWidget != null) const SizedBox(height: 24),
            if (actionWidget != null) actionWidget,
          ],
        ),
      ),
    );
  }
}
