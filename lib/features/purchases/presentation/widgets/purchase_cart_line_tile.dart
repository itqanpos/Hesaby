// lib/features/purchases/presentation/widgets/purchase_cart_line_tile.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/entities/purchase_cart_line.dart';
import '../state/purchase_providers.dart';

/// A single line in the purchase cart — single-row layout.
///
/// Quantity and unit cost are edited **by typing** in each field. The tile
/// commits values on submit / focus-loss. When the corresponding line is
/// added via [PurchaseResultsList], [focusedCartLineProvider] is set to its
/// key, and the tile auto-focuses its quantity field — matching the POS
/// mobile experience.
class PurchaseCartLineTile extends ConsumerStatefulWidget {
  const PurchaseCartLineTile({
    super.key,
    required this.line,
    required this.onSetQuantity,
    required this.onSetCost,
    required this.onRemove,
  });

  final PurchaseCartLine line;
  final bool Function(double quantity) onSetQuantity;
  final bool Function(double cost) onSetCost;
  final VoidCallback onRemove;

  @override
  ConsumerState<PurchaseCartLineTile> createState() =>
      _PurchaseCartLineTileState();
}

class _PurchaseCartLineTileState
    extends ConsumerState<PurchaseCartLineTile> {
  late final TextEditingController _quantityController;
  late final TextEditingController _costController;
  late final FocusNode _quantityFocus;
  late final FocusNode _costFocus;

  String? _quantityError;
  String? _costError;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: _formatNumber(widget.line.quantity),
    );
    _costController = TextEditingController(
      text: _formatNumber(widget.line.unitCost),
    );
    _quantityFocus = FocusNode()..addListener(_onQuantityFocusChange);
    _costFocus = FocusNode()..addListener(_onCostFocusChange);

    // إذا تمت إضافة هذا السطر للتو، اطلب التركيز في أول إطار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(focusedCartLineProvider) == widget.line.key) {
        _focusQuantitySelectAll();
        ref.read(focusedCartLineProvider.notifier).state = null;
      }
    });
  }

  @override
  void dispose() {
    _quantityFocus.removeListener(_onQuantityFocusChange);
    _costFocus.removeListener(_onCostFocusChange);
    _quantityFocus.dispose();
    _costFocus.dispose();
    _quantityController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PurchaseCartLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.quantity != widget.line.quantity &&
        !_quantityFocus.hasFocus) {
      _quantityController.text = _formatNumber(widget.line.quantity);
    }
    if (oldWidget.line.unitCost != widget.line.unitCost &&
        !_costFocus.hasFocus) {
      _costController.text = _formatNumber(widget.line.unitCost);
    }
  }

  // ---------------------------------------------------------------------------
  // Focus — rule 29: explicit TextInput.show
  // ---------------------------------------------------------------------------

  void _focusQuantitySelectAll() {
    _quantityFocus.requestFocus();
    _quantityController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _quantityController.text.length,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_quantityFocus.hasFocus) return;
      SystemChannels.textInput
          .invokeMethod<void>('TextInput.show')
          .ignore();
    });
  }

  // ---------------------------------------------------------------------------
  // Commit helpers
  // ---------------------------------------------------------------------------

  void _onQuantityFocusChange() {
    if (mounted) setState(() {});
    if (!_quantityFocus.hasFocus) _commitQuantity();
  }

  void _onCostFocusChange() {
    if (mounted) setState(() {});
    if (!_costFocus.hasFocus) _commitCost();
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
      if (mounted) setState(() => _quantityError = 'كمية مرفوضة');
      _quantityController.text = _formatNumber(widget.line.quantity);
      return;
    }

    if (mounted) {
      setState(() {
        _quantityError = null;
        _quantityController.text = _formatNumber(parsed);
      });
    }
  }

  void _commitCost() {
    final String raw = _costController.text.trim();
    if (raw.isEmpty) {
      _resetCost();
      return;
    }
    final double? parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0) {
      _resetCost();
      if (mounted) setState(() => _costError = 'رقم غير صحيح');
      return;
    }

    final bool accepted = widget.onSetCost(parsed);
    if (!accepted) {
      if (mounted) setState(() => _costError = 'قيمة مرفوضة');
      _costController.text = _formatNumber(widget.line.unitCost);
      return;
    }

    if (mounted) {
      setState(() {
        _costError = null;
        _costController.text = _formatNumber(parsed);
      });
    }
  }

  void _resetQuantity() {
    _quantityController.text = _formatNumber(widget.line.quantity);
    if (_quantityError != null && mounted) {
      setState(() => _quantityError = null);
    }
  }

  void _resetCost() {
    _costController.text = _formatNumber(widget.line.unitCost);
    if (_costError != null && mounted) {
      setState(() => _costError = null);
    }
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
    final PurchaseCartLine line = widget.line;

    // يلتقط تغييرات provider بعد أن يكون الـ tile موجودًا بالفعل
    // (مثال: زيادة سطر موجود عبر البحث).
    ref.listen<String?>(focusedCartLineProvider, (previous, next) {
      if (next == line.key) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusQuantitySelectAll();
            ref.read(focusedCartLineProvider.notifier).state = null;
          }
        });
      }
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
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
          SizedBox(
            width: 68,
            child: _CompactField(
              controller: _costController,
              focusNode: _costFocus,
              errorText: _costError,
              onSubmitted: _commitCost,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: Text(
              AppFormatters.money(line.lineTotal),
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _IconTap(
            tooltip: 'حذف من السلة',
            icon: Icons.close,
            onTap: widget.onRemove,
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
        child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
