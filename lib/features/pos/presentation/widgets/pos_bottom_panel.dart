// lib/features/pos/presentation/widgets/pos_bottom_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../dialogs/pos_payment_dialog.dart';
import '../state/pos_providers.dart';

/// Compact bottom panel used by the POS **mobile** layout.
///
/// Replaces the taller combination of `PosTotalsBar` + `PosPayButton` that
/// is still used on tablet and desktop.
///
/// Business rules applied here:
/// * **Default tax** — when the cart has no explicit `taxAmount`, the
///   panel applies `defaultTaxRate` from company settings to
///   `(subtotal − discount)`.
/// * **Max discount** — the discount field rejects any value above
///   `maxDiscountPercent` from company settings, clamping it to the
///   allowed ceiling.
class PosBottomPanel extends ConsumerWidget {
  const PosBottomPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final PosCart cart = ref.watch(posCartProvider);
    final double defaultTaxRate = ref.watch(defaultTaxRateProvider);
    final double maxDiscountPercent = ref.watch(maxDiscountPercentProvider);

    final double afterDiscount = cart.subtotal - cart.discount;
    final double effectiveTax = cart.taxAmount > 0
        ? cart.taxAmount
        : afterDiscount * defaultTaxRate / 100;
    final double effectiveTotal = afterDiscount + effectiveTax;
    final double maxDiscountValue = cart.subtotal * maxDiscountPercent / 100;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _TopRow(
                lineCount: cart.lines.length,
                discount: cart.discount,
                maxDiscountValue: maxDiscountValue,
              ),
              const SizedBox(height: 6),
              _TotalRow(total: effectiveTotal),
              const SizedBox(height: 8),
              _PayButton(isEmpty: cart.isEmpty),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Top row — item count + editable discount
// ============================================================================

class _TopRow extends ConsumerWidget {
  const _TopRow({
    required this.lineCount,
    required this.discount,
    required this.maxDiscountValue,
  });

  final int lineCount;
  final double discount;
  final double maxDiscountValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Icon(
          Icons.shopping_bag_outlined,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          'الأصناف: $lineCount',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          'الخصم',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        _DiscountField(
          discount: discount,
          maxAllowed: maxDiscountValue,
          onChanged: (double value) =>
              ref.read(posCartProvider.notifier).setDiscount(value),
        ),
        const SizedBox(width: 4),
        Text(
          'ج.م',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Total row — the emphasized "الصافي"
// ============================================================================

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.total});

  final double total;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          'الصافي',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          _money.format(total),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Pay button
// ============================================================================

class _PayButton extends StatelessWidget {
  const _PayButton({required this.isEmpty});

  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'دفع',
      icon: Icons.check_circle_outline,
      expanded: true,
      size: AppButtonSize.large,
      onPressed:
          isEmpty ? null : () => showPosPaymentDialog(context: context),
    );
  }
}

// ============================================================================
// Discount field — inline editable, clamped to the allowed maximum
// ============================================================================

class _DiscountField extends StatefulWidget {
  const _DiscountField({
    required this.discount,
    required this.maxAllowed,
    required this.onChanged,
  });

  final double discount;

  /// Highest value the field will accept. Values above it are clamped.
  final double maxAllowed;

  final ValueChanged<double> onChanged;

  @override
  State<_DiscountField> createState() => _DiscountFieldState();
}

class _DiscountFieldState extends State<_DiscountField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatDiscount(widget.discount),
    );
    _focusNode = FocusNode();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(_DiscountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.discount != oldWidget.discount && !_focusNode.hasFocus) {
      _controller.text = _formatDiscount(widget.discount);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final double parsed = double.tryParse(_controller.text.trim()) ?? 0;

    // Clamp to the allowed maximum. The clamp is silent from the field's
    // perspective; the caller receives the clamped value.
    final double accepted = parsed > widget.maxAllowed
        ? widget.maxAllowed
        : (parsed < 0 ? 0 : parsed);

    widget.onChanged(accepted);
  }

  static String _formatDiscount(double value) {
    if (value == 0) {
      return '';
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: 84,
      height: 32,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: '0',
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
