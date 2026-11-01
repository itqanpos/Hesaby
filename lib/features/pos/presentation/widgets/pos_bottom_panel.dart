// lib/features/pos/presentation/widgets/pos_bottom_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../shared/widgets/app_button.dart';
import '../../../companies/presentation/widgets/subscription_guard.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../domain/entities/pos_cart.dart';
import '../dialogs/pos_payment_dialog.dart';
import '../state/pos_providers.dart';

/// Compact bottom panel used by the POS **mobile** layout.
class PosBottomPanel extends ConsumerWidget {
  const PosBottomPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final PosCart cart = ref.watch(posCartProvider);
    final PosTotals totals = ref.watch(posTotalsProvider);
    final double maxDiscountPercent = ref.watch(maxDiscountPercentProvider);

    // Same total as the payment dialog and the receipt.
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
              if (totals.taxAmount > 0) ...<Widget>[
                _TaxRow(tax: totals.taxAmount),
                const SizedBox(height: 2),
              ],
              _TotalRow(total: totals.total),
              const SizedBox(height: 8),
              _ActionButtons(isEmpty: cart.isEmpty),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _TaxRow extends StatelessWidget {
  const _TaxRow({required this.tax});

  final double tax;

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
      children: <Widget>[
        Text(
          'الضريبة',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          _money.format(tax),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

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

/// أزرار أسفل الشاشة: إلغاء + دفع
class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.isEmpty});

  final bool isEmpty;

  Future<void> _handleCancel(BuildContext context, WidgetRef ref) async {
    if (isEmpty) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: const Text(
          'هل أنت متأكد من إلغاء الفاتورة الحالية وحذف جميع الأصناف؟',
        ),
        actions: <Widget>[
          AppButton(
            label: 'تراجع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: 'نعم، إلغاء',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ref.read(posCartProvider.notifier).reset();
    }
  }

  Future<void> _handlePay(BuildContext context, WidgetRef ref) async {
    final bool allowed = await SubscriptionGuard.ensureCanWrite(
      context: context,
      ref: ref,
    );
    if (!allowed || !context.mounted) return;

    await showPosPaymentDialog(context: context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: <Widget>[
        Expanded(
          child: AppButton(
            label: 'إلغاء',
            icon: Icons.delete_outline,
            variant: AppButtonVariant.outline,
            expanded: true,
            size: AppButtonSize.large,
            onPressed: isEmpty ? null : () => _handleCancel(context, ref),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: AppButton(
            label: 'دفع',
            icon: Icons.check_circle_outline,
            expanded: true,
            size: AppButtonSize.large,
            onPressed: isEmpty ? null : () => _handlePay(context, ref),
          ),
        ),
      ],
    );
  }
}

class _DiscountField extends StatefulWidget {
  const _DiscountField({
    required this.discount,
    required this.maxAllowed,
    required this.onChanged,
  });

  final double discount;
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
