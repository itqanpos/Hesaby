// lib/features/pos/presentation/widgets/pos_cart_line_tile.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/pos_cart_line.dart';

/// A single line in the POS cart.
///
/// Layout (RTL):
/// ```
///  بيبسي 1 لتر                    × 12.00    ✕
///  [−]  2  [+]   قطعة                  24.00
/// ```
///
/// * The first row shows the product name, the unit price, and a small
///   remove button.
/// * The second row shows the quantity controls, the unit label, and the
///   line total.
///
/// The tile is purely presentational: it exposes three callbacks and does
/// not read any provider. The parent widget (`PosCartList`) is responsible
/// for routing those callbacks to `posCartProvider.notifier`.
class PosCartLineTile extends StatelessWidget {
  const PosCartLineTile({
    super.key,
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  /// The line to render.
  final PosCartLine line;

  /// Called when the cashier taps the `[+]` button.
  ///
  /// The handler is responsible for deciding whether the increment is
  /// allowed (for example, based on the available stock) and for
  /// surfacing any feedback to the cashier.
  final VoidCallback onIncrement;

  /// Called when the cashier taps the `[−]` button.
  final VoidCallback onDecrement;

  /// Called when the cashier taps the small remove button on the line.
  final VoidCallback onRemove;

  // ---------------------------------------------------------------------------
  // Formatters (created once per build; lightweight)
  // ---------------------------------------------------------------------------

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // -----------------------------------------------------------------
          // Row 1 — name + unit price + remove
          // -----------------------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  line.productName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '× ${_money.format(line.unitPrice)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              _RemoveButton(onPressed: onRemove),
            ],
          ),

          const SizedBox(height: 6),

          // -----------------------------------------------------------------
          // Row 2 — quantity controls + unit + line total
          // -----------------------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              _QuantityStepper(
                quantity: line.quantity,
                canIncrease: line.canIncrease,
                onDecrement: onDecrement,
                onIncrement: onIncrement,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  line.unitName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _money.format(line.lineTotal),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Quantity stepper — [−] value [+]
// ============================================================================

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.canIncrease,
    required this.onDecrement,
    required this.onIncrement,
  });

  final double quantity;

  /// When `false`, the `[+]` button is disabled and its colour reflects
  /// the disabled state. The parent handler still receives the tap when
  /// enabled, so it can surface a specific feedback message.
  final bool canIncrease;

  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StepperButton(
            icon: Icons.remove,
            onPressed: onDecrement,
            enabled: true,
          ),
          SizedBox(
            width: 40,
            child: Center(
              child: Text(
                PosCartLineTile._formatQuantity(quantity),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            onPressed: onIncrement,
            enabled: canIncrease,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.onPressed,
    required this.enabled,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: enabled ? onPressed : null,
        icon: Icon(
          icon,
          size: 18,
          color: enabled ? scheme.onSurface : scheme.outlineVariant,
        ),
      ),
    );
  }
}

// ============================================================================
// Remove button — small ✕
// ============================================================================

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 16,
        tooltip: 'حذف من السلة',
        onPressed: onPressed,
        icon: Icon(
          Icons.close,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
