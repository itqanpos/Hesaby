// lib/shared/widgets/app_button.dart
import 'package:flutter/material.dart';

/// Visual variants supported by [AppButton].
enum AppButtonVariant { primary, secondary, outline, text, danger }

/// Size presets supported by [AppButton].
enum AppButtonSize { small, medium, large }

/// Standard button used across HESABI.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;

  bool get _isEnabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final EdgeInsetsGeometry padding = _paddingFor(size);
    final Widget child = _buildChild(scheme);
    final VoidCallback? effectiveOnPressed = _isEnabled ? onPressed : null;

    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(padding: padding),
          child: child,
        ),
      AppButtonVariant.secondary => FilledButton.tonal(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(padding: padding),
          child: child,
        ),
      AppButtonVariant.outline => OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(padding: padding),
          child: child,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(padding: padding),
          child: child,
        ),
      AppButtonVariant.danger => FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            padding: padding,
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          child: child,
        ),
    };

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _buildChild(ColorScheme scheme) {
    if (isLoading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _foregroundColor(scheme),
        ),
      );
    }

    final IconData? iconData = icon;
    if (iconData == null) {
      return Text(label);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(iconData, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }

  Color _foregroundColor(ColorScheme scheme) => switch (variant) {
        AppButtonVariant.primary => scheme.onPrimary,
        AppButtonVariant.secondary => scheme.onSecondaryContainer,
        AppButtonVariant.outline || AppButtonVariant.text => scheme.primary,
        AppButtonVariant.danger => scheme.onError,
      };

  EdgeInsetsGeometry _paddingFor(AppButtonSize value) => switch (value) {
        AppButtonSize.small => const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        AppButtonSize.medium => const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
        AppButtonSize.large => const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 18,
          ),
      };
}
