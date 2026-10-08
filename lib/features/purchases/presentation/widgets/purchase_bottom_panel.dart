// lib/features/purchases/presentation/widgets/purchase_bottom_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/purchase_cart.dart';
import '../state/purchase_providers.dart';

/// Bottom panel: totals + discount/tax + save actions.
///
/// Two save modes:
/// * **حفظ كمسودة** — persists without touching stock.
/// * **حفظ وتأكيد** — persists and immediately confirms (adds stock).
class PurchaseBottomPanel extends ConsumerStatefulWidget {
  const PurchaseBottomPanel({
    super.key,
    required this.onSaveDraft,
    required this.onSaveAndConfirm,
    this.isSubmitting = false,
  });

  /// Invoked when the user taps "حفظ كمسودة".
  final VoidCallback onSaveDraft;

  /// Invoked when the user taps "حفظ وتأكيد".
  final VoidCallback onSaveAndConfirm;

  /// Whether a save is in progress.
  final bool isSubmitting;

  @override
  ConsumerState<PurchaseBottomPanel> createState() =>
      _PurchaseBottomPanelState();
}

class _PurchaseBottomPanelState
    extends ConsumerState<PurchaseBottomPanel> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  late final TextEditingController _discountController;
  late final TextEditingController _taxController;

  @override
  void initState() {
    super.initState();
    final PurchaseCart cart = ref.read(purchaseCartProvider);
    _discountController = TextEditingController(
      text: cart.discount > 0 ? _formatNumber(cart.discount) : '',
    );
    _taxController = TextEditingController(
      text: cart.taxAmount > 0 ? _formatNumber(cart.taxAmount) : '',
    );
  }

  @override
  void dispose() {
    _discountController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  static String _formatNumber(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  void _onDiscountChanged(String raw) {
    final double v = double.tryParse(raw.trim()) ?? 0;
    ref.read(purchaseCartProvider.notifier).setDiscount(v);
  }

  void _onTaxChanged(String raw) {
    final double v = double.tryParse(raw.trim()) ?? 0;
    ref.read(purchaseCartProvider.notifier).setTaxAmount(v);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PurchaseCart cart = ref.watch(purchaseCartProvider);

    final bool canSave = cart.isNotEmpty &&
        cart.hasSupplier &&
        cart.hasPurchaseDate &&
        !widget.isSubmitting;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ---- Discount + Tax row ----
          Row(
            children: <Widget>[
              Expanded(
                child: _SmallNumberField(
                  controller: _discountController,
                  label: 'الخصم',
                  onChanged: _onDiscountChanged,
                  enabled: !widget.isSubmitting,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SmallNumberField(
                  controller: _taxController,
                  label: 'الضريبة',
                  onChanged: _onTaxChanged,
                  enabled: !widget.isSubmitting,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ---- Subtotals ----
          _row(theme, 'المجموع الفرعي', _money.format(cart.subtotal)),
          if (cart.discount > 0)
            _row(theme, 'الخصم', '- ${_money.format(cart.discount)}'),
          if (cart.taxAmount > 0)
            _row(theme, 'الضريبة', '+ ${_money.format(cart.taxAmount)}'),
          const Divider(height: 12),
          _row(
            theme,
            'الإجمالي',
            _money.format(cart.total),
            emphasized: true,
          ),
          const SizedBox(height: 10),

          // ---- Save actions ----
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: 'حفظ كمسودة',
                  icon: Icons.save_outlined,
                  variant: AppButtonVariant.secondary,
                  expanded: true,
                  onPressed: canSave ? widget.onSaveDraft : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'حفظ وتأكيد',
                  icon: Icons.check_circle_outline,
                  expanded: true,
                  isLoading: widget.isSubmitting,
                  onPressed: canSave ? widget.onSaveAndConfirm : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: (emphasized
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.bodySmall)
                  ?.copyWith(
                fontWeight: emphasized ? FontWeight.w700 : null,
              ),
            ),
          ),
          Text(
            value,
            style: (emphasized
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium)
                ?.copyWith(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
              color: emphasized ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Small number field
// ============================================================================

class _SmallNumberField extends StatelessWidget {
  const _SmallNumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
