// lib/features/pos/presentation/widgets/pos_cart_line_tile.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/pos_cart_line.dart';

/// A single line in the POS cart — **single row layout**.
///
/// Layout (RTL):
/// ```
/// ┌──────────────────────────────────────────────────────────────┐
/// │ بيبسي 1 لتر  [2] قطعة  [12.00] 24.00 ج.م  ✕                  │
/// └──────────────────────────────────────────────────────────────┘
/// ```
///
/// The price range hint appears **only while the price field is focused**,
/// as a small overlay above the line — it does not consume vertical space
/// in the steady state.
class PosCartLineTile extends StatefulWidget {
  const PosCartLineTile({
    super.key,
    required this.line,
    required this.onSetQuantity,
    required this.onSetPrice,
    required this.onRemove,
  });

  final PosCartLine line;

  /// Commits a new quantity. Returns `true` when accepted.
  final bool Function(double quantity) onSetQuantity;

  /// Commits a new unit price. Returns `true` when accepted.
  final bool Function(double price) onSetPrice;

  final VoidCallback onRemove;

  @override
  State<PosCartLineTile> createState() => _PosCartLineTileState();
}

class _PosCartLineTileState extends State<PosCartLineTile> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;
  late final FocusNode _quantityFocus;
  late final FocusNode _priceFocus;

  String? _quantityError;
  String? _priceError;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: _formatQuantity(widget.line.quantity),
    );
    _priceController = TextEditingController(
      text: _formatNumber(widget.line.unitPrice),
    );
    _quantityFocus = FocusNode()..addListener(_onQuantityFocusChange);
    _priceFocus = FocusNode()..addListener(_onPriceFocusChange);
  }

  @override
  void dispose() {
    _quantityFocus.removeListener(_onQuantityFocusChange);
    _priceFocus.removeListener(_onPriceFocusChange);
    _quantityFocus.dispose();
    _priceFocus.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PosCartLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.quantity != widget.line.quantity &&
        !_quantityFocus.hasFocus) {
      _quantityController.text = _formatQuantity(widget.line.quantity);
    }
    if (oldWidget.line.unitPrice != widget.line.unitPrice &&
        !_priceFocus.hasFocus) {
      _priceController.text = _formatNumber(widget.line.unitPrice);
    }
  }

  // ---------------------------------------------------------------------------
  // Commit helpers
  // ---------------------------------------------------------------------------

  void _onQuantityFocusChange() {
    if (mounted) setState(() {});
    if (!_quantityFocus.hasFocus) _commitQuantity();
  }

  void _onPriceFocusChange() {
    if (mounted) setState(() {});
    if (!_priceFocus.hasFocus) _commitPrice();
  }

  void _commitQuantity() {
    final String raw = _quantityController.text.trim();
    if (raw.isEmpty) {
      _resetQuantity();
      return;
    }
    final double? parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      _resetQuantity();
      if (mounted) setState(() => _quantityError = 'رقم غير صحيح');
      return;
    }

    final bool accepted = widget.onSetQuantity(parsed);
    if (!accepted) {
      final double? available = widget.line.availableStock;
      if (mounted) {
        setState(() {
          _quantityError = available != null
              ? 'المتاح ${_formatQuantity(available)}'
              : 'كمية مرفوضة';
        });
      }
      _quantityController.text = _formatQuantity(widget.line.quantity);
      return;
    }

    if (mounted) {
      setState(() {
        _quantityError = null;
        _quantityController.text = _formatQuantity(parsed);
      });
    }
  }

  void _commitPrice() {
    final String raw = _priceController.text.trim();
    if (raw.isEmpty) {
      _resetPrice();
      return;
    }
    final double? parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0) {
      _resetPrice();
      if (mounted) setState(() => _priceError = 'رقم غير صحيح');
      return;
    }

    final bool accepted = widget.onSetPrice(parsed);
    if (!accepted) {
      if (mounted) setState(() => _priceError = 'خارج النطاق');
      _priceController.text = _formatNumber(widget.line.unitPrice);
      return;
    }

    if (mounted) {
      setState(() {
        _priceError = null;
        _priceController.text = _formatNumber(parsed);
      });
    }
  }

  void _resetQuantity() {
    _quantityController.text = _formatQuantity(widget.line.quantity);
    if (_quantityError != null && mounted) {
      setState(() => _quantityError = null);
    }
  }

  void _resetPrice() {
    _priceController.text = _formatNumber(widget.line.unitPrice);
    if (_priceError != null && mounted) {
      setState(() => _priceError = null);
    }
  }

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static String _formatNumber(double value) {
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
    final PosCartLine line = widget.line;

    // Whether to show the price-range overlay: only while the price field
    // is focused (or the price has an active error).
    final bool showPriceRangeOverlay =
        line.hasPriceRange && (_priceFocus.hasFocus || _priceError != null);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ---- Price range overlay (shown only on price focus/error) ----
          if (showPriceRangeOverlay)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 8, left: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Icon(
                    _priceError != null
                        ? Icons.error_outline
                        : Icons.info_outline,
                    size: 12,
                    color: _priceError != null
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _priceError != null
                        ? 'النطاق المسموح: '
                            '${line.minSellingPrice == null ? '—' : _money.format(line.minSellingPrice!)}'
                            ' – '
                            '${line.maxSellingPrice == null ? '—' : _money.format(line.maxSellingPrice!)}'
                        : 'النطاق المسموح: '
                            '${line.minSellingPrice == null ? '—' : _money.format(line.minSellingPrice!)}'
                            ' – '
                            '${line.maxSellingPrice == null ? '—' : _money.format(line.maxSellingPrice!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _priceError != null
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

          // ---- Single row: name | qty | unit | price | total | remove ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // ---- Product name ----
              Expanded(
                flex: 4,
                child: Text(
                  line.productName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),

              // ---- Quantity ----
              SizedBox(
                width: 52,
                child: _CompactField(
                  controller: _quantityController,
                  focusNode: _quantityFocus,
                  errorText: _quantityError,
                  onSubmitted: _commitQuantity,
                ),
              ),
              const SizedBox(width: 4),

              // ---- Unit name ----
              SizedBox(
                width: 44,
                child: Text(
                  line.unitName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 4),

              // ---- Unit price ----
              SizedBox(
                width: 68,
                child: _CompactField(
                  controller: _priceController,
                  focusNode: _priceFocus,
                  errorText: _priceError,
                  onSubmitted: _commitPrice,
                ),
              ),
              const SizedBox(width: 6),

              // ---- Line total ----
              SizedBox(
                width: 72,
                child: Text(
                  _money.format(line.lineTotal),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // ---- Remove ----
              _IconTap(
                tooltip: 'حذف من السلة',
                icon: Icons.close,
                onTap: widget.onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Compact number field
// ============================================================================

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasError = errorText != null;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      textInputAction: TextInputAction.done,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      onSubmitted: (_) => onSubmitted(),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: hasError
                ? theme.colorScheme.error
                : theme.colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Small icon tap target
// ============================================================================

class _IconTap extends StatelessWidget {
  const _IconTap({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
