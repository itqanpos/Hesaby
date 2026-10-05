// lib/features/pos/presentation/widgets/pos_bottom_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../dialogs/pos_payment_dialog.dart';
import '../state/pos_providers.dart';

/// Compact bottom panel used by the POS **mobile** layout.
///
/// Replaces the taller combination of `PosTotalsBar` + `PosPayButton` that
/// is still used on tablet and desktop. The goal here is to keep the whole
/// panel under ~170 dp on a typical phone, so the cart list above stays
/// readable even while the soft keyboard is open.
///
/// Layout, top to bottom:
/// ```
/// ┌──────────────────────────────────────────────┐
/// │  🛍  الأصناف: 3            الخصم [___] ج.م   │
/// │  ──────────────────────────────────────────  │
/// │  الصافي                        1,250.00 ج.م  │
/// │  ┌────────────────────────────────────────┐  │
/// │  │           ✓  دفع                       │  │
/// │  └────────────────────────────────────────┘  │
/// └──────────────────────────────────────────────┘
/// ```
///
/// The panel is purely presentational: it reads `posTotalsProvider` and
/// delegates every mutation back to `posCartProvider`. The pay button
/// opens `showPosPaymentDialog` directly — no `PosPayButton` is reused,
/// because that widget also renders the running total, which would
/// duplicate the "الصافي" row above.
class PosBottomPanel extends ConsumerWidget {
  const PosBottomPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final PosTotals totals = ref.watch(posTotalsProvider);

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
              _TopRow(totals: totals),
              const SizedBox(height: 6),
              _TotalRow(total: totals.total),
              const SizedBox(height: 8),
              _PayButton(isEmpty: totals.isEmpty),
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
  const _TopRow({required this.totals});

  final PosTotals totals;

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
          'الأصناف: ${totals.lineCount}',
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
          discount: totals.discount,
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
// Pay button — opens the payment dialog
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
      onPressed: isEmpty
          ? null
          : () => showPosPaymentDialog(context: context),
    );
  }
}

// ============================================================================
// Discount field — inline editable, no external dependencies
// ============================================================================

/// Compact editable discount field.
///
/// Mirrors the behaviour of the private `_DiscountRow` in
/// `pos_totals_bar.dart` but at a smaller footprint, and without the
/// "ج.م" suffix inside the field itself (the suffix is rendered by the
/// parent row). Kept private here to avoid coupling the two files.
class _DiscountField extends StatefulWidget {
  const _DiscountField({
    required this.discount,
    required this.onChanged,
  });

  final double discount;
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
    widget.onChanged(parsed);
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
