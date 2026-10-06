// lib/features/pos/presentation/dialogs/pos_unit_quick_add_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../products/domain/entities/product.dart';
import '../state/pos_providers.dart';

/// Opens a compact bottom sheet that lets the cashier confirm the quantity
/// and unit price before adding a single unit of [product] to the cart.
///
/// The sheet is intentionally small: its content fits in a single viewport
/// even with the soft keyboard open. It uses `viewInsets` to push the
/// "Add" button above the keyboard, so nothing is obscured while typing.
///
/// Returns `true` when a line was added, `null`/`false` otherwise.
Future<bool?> showPosUnitQuickAddSheet({
  required BuildContext context,
  required Product product,
  required String unitId,
  required String unitName,
  required double conversionFactor,
  required double defaultPrice,
  double? minSellingPrice,
  double? maxSellingPrice,
  double? availableStock,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => _PosUnitQuickAddSheet(
      product: product,
      unitId: unitId,
      unitName: unitName,
      conversionFactor: conversionFactor,
      defaultPrice: defaultPrice,
      minSellingPrice: minSellingPrice,
      maxSellingPrice: maxSellingPrice,
      availableStock: availableStock,
    ),
  );
}

class _PosUnitQuickAddSheet extends ConsumerStatefulWidget {
  const _PosUnitQuickAddSheet({
    required this.product,
    required this.unitId,
    required this.unitName,
    required this.conversionFactor,
    required this.defaultPrice,
    required this.minSellingPrice,
    required this.maxSellingPrice,
    required this.availableStock,
  });

  final Product product;
  final String unitId;
  final String unitName;
  final double conversionFactor;
  final double defaultPrice;
  final double? minSellingPrice;
  final double? maxSellingPrice;
  final double? availableStock;

  @override
  ConsumerState<_PosUnitQuickAddSheet> createState() =>
      _PosUnitQuickAddSheetState();
}

class _PosUnitQuickAddSheetState
    extends ConsumerState<_PosUnitQuickAddSheet> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: '1');
    _priceController = TextEditingController(
      text: _formatNumber(widget.defaultPrice),
    );
    _quantityController.addListener(_rebuild);
    _priceController.addListener(_rebuild);
  }

  @override
  void dispose() {
    _quantityController.removeListener(_rebuild);
    _priceController.removeListener(_rebuild);
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  double get _quantity =>
      double.tryParse(_quantityController.text.trim()) ?? 0;

  double get _unitPrice =>
      double.tryParse(_priceController.text.trim()) ?? 0;

  double get _lineTotal => _quantity * _unitPrice;

  bool get _exceedsStock =>
      widget.availableStock != null && _quantity > widget.availableStock!;

  bool get _priceBelowMin =>
      widget.minSellingPrice != null &&
      _unitPrice < widget.minSellingPrice!;

  bool get _priceAboveMax =>
      widget.maxSellingPrice != null &&
      _unitPrice > widget.maxSellingPrice!;

  bool get _canSubmit =>
      _quantity > 0 &&
      !_exceedsStock &&
      !_priceBelowMin &&
      !_priceAboveMax;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _increment() {
    final double next = _quantity + 1;
    if (widget.availableStock != null && next > widget.availableStock!) {
      return;
    }
    _quantityController.text = _formatNumber(next);
  }

  void _decrement() {
    final double next = _quantity > 1 ? _quantity - 1 : 1;
    _quantityController.text = _formatNumber(next);
  }

  void _submit() {
    if (!_canSubmit) return;

    final bool added = ref.read(posCartProvider.notifier).addLine(
          productId: widget.product.id,
          productName: widget.product.name,
          unitId: widget.unitId,
          unitName: widget.unitName,
          conversionFactor: widget.conversionFactor,
          quantity: _quantity,
          unitPrice: _unitPrice,
          minSellingPrice: widget.minSellingPrice,
          maxSellingPrice: widget.maxSellingPrice,
          availableStock: widget.availableStock,
        );

    Navigator.of(context).pop(added);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      // Push the sheet content above the soft keyboard.
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- Header ----
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          widget.product.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'الوحدة: ${widget.unitName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // ---- Quantity ----
              Text('الكمية', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  IconButton.filledTonal(
                    onPressed: _decrement,
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _quantityController,
                      textAlign: TextAlign.center,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.]'),
                        ),
                      ],
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _increment,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (widget.availableStock != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'المتاح: ${_formatNumber(widget.availableStock!)} '
                  '${widget.unitName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _exceedsStock
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // ---- Price ----
              Text('سعر الوحدة', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              TextField(
                controller: _priceController,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                  suffixText: 'ج.م',
                  errorText: (_priceBelowMin || _priceAboveMax)
                      ? 'السعر خارج النطاق المسموح.'
                      : null,
                ),
              ),
              if (widget.minSellingPrice != null ||
                  widget.maxSellingPrice != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'النطاق: '
                  '${widget.minSellingPrice == null ? '—' : _money.format(widget.minSellingPrice)}'
                  ' – '
                  '${widget.maxSellingPrice == null ? '—' : _money.format(widget.maxSellingPrice)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: (_priceBelowMin || _priceAboveMax)
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ---- Total ----
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        'الإجمالي',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _money.format(_lineTotal),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ---- Submit ----
              AppButton(
                label: 'إضافة إلى السلة',
                icon: Icons.add_shopping_cart,
                expanded: true,
                size: AppButtonSize.large,
                onPressed: _canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
