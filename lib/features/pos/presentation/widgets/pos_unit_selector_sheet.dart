// lib/features/pos/presentation/widgets/pos_unit_selector_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../state/pos_providers.dart';

/// Opens the POS unit selector sheet for [product].
///
/// The sheet lets the cashier pick a unit (default or an additional one
/// registered in `product_units`), a quantity, and a unit price within the
/// product's allowed range. Tapping "إضافة إلى السلة" adds one line to the
/// cart.
///
/// Returns `true` when a line was added, `false` or `null` otherwise.
Future<bool?> showPosUnitSelectorSheet({
  required BuildContext context,
  required Product product,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => _PosUnitSelectorSheet(
      product: product,
    ),
  );
}

// ============================================================================
// Sheet
// ============================================================================

class _PosUnitSelectorSheet extends ConsumerStatefulWidget {
  const _PosUnitSelectorSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_PosUnitSelectorSheet> createState() =>
      _PosUnitSelectorSheetState();
}

class _PosUnitSelectorSheetState
    extends ConsumerState<_PosUnitSelectorSheet> {
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;
  late final FocusNode _quantityFocus;

  String? _selectedUnitId;
  bool _initialized = false;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: '1');
    _priceController = TextEditingController(
      text: _formatNumber(widget.product.sellingPrice),
    );
    _quantityFocus = FocusNode();
    _selectedUnitId = widget.product.defaultUnitId;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _quantityFocus.dispose();
    super.dispose();
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

  /// Returns the ordered list of units selectable for the product.
  static List<Unit> _availableUnits(
    Product product,
    List<Unit> allUnits,
    List<ProductUnit> extras,
  ) {
    final List<Unit> result = <Unit>[];
    final Set<String> seen = <String>{};

    for (final Unit unit in allUnits) {
      if (unit.id == product.defaultUnitId) {
        result.add(unit);
        seen.add(unit.id);
        break;
      }
    }
    for (final ProductUnit extra in extras) {
      for (final Unit unit in allUnits) {
        if (unit.id == extra.unitId && seen.add(unit.id)) {
          result.add(unit);
          break;
        }
      }
    }
    return result;
  }

  static ProductUnit? _extraFor(String unitId, List<ProductUnit> extras) {
    for (final ProductUnit extra in extras) {
      if (extra.unitId == unitId) {
        return extra;
      }
    }
    return null;
  }

  double? _effectiveMin(String unitId, List<ProductUnit> extras) {
    if (unitId == widget.product.defaultUnitId) {
      return widget.product.minSellingPrice;
    }
    final ProductUnit? extra = _extraFor(unitId, extras);
    if (extra?.minSellingPrice != null) {
      return extra!.minSellingPrice;
    }
    final double? baseMin = widget.product.minSellingPrice;
    if (baseMin == null || extra == null) {
      return null;
    }
    return baseMin * extra.conversionFactor;
  }

  double? _effectiveMax(String unitId, List<ProductUnit> extras) {
    if (unitId == widget.product.defaultUnitId) {
      return widget.product.maxSellingPrice;
    }
    final ProductUnit? extra = _extraFor(unitId, extras);
    if (extra?.maxSellingPrice != null) {
      return extra!.maxSellingPrice;
    }
    final double? baseMax = widget.product.maxSellingPrice;
    if (baseMax == null || extra == null) {
      return null;
    }
    return baseMax * extra.conversionFactor;
  }

  double _suggestedPrice(String unitId, List<ProductUnit> extras) {
    if (unitId == widget.product.defaultUnitId) {
      return widget.product.sellingPrice;
    }
    final ProductUnit? extra = _extraFor(unitId, extras);
    if (extra == null) {
      return widget.product.sellingPrice;
    }
    if (extra.sellingPrice != null) {
      return extra.sellingPrice!;
    }
    return widget.product.sellingPrice * extra.conversionFactor;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  void _submit({
    required List<ProductUnit> extras,
    required List<Unit> availableUnits,
  }) {
    if (_quantity <= 0) {
      return;
    }
    final String? unitId = _selectedUnitId;
    if (unitId == null) {
      return;
    }

    final double? minPrice = _effectiveMin(unitId, extras);
    final double? maxPrice = _effectiveMax(unitId, extras);
    if (minPrice != null && _unitPrice < minPrice) {
      return;
    }
    if (maxPrice != null && _unitPrice > maxPrice) {
      return;
    }

    Unit? selectedUnit;
    for (final Unit unit in availableUnits) {
      if (unit.id == unitId) {
        selectedUnit = unit;
        break;
      }
    }
    if (selectedUnit == null) {
      return;
    }

    final ProductUnit? extra = _extraFor(unitId, extras);
    final double conversionFactor = extra?.conversionFactor ?? 1;

    ref.read(posCartProvider.notifier).addLine(
          productId: widget.product.id,
          productName: widget.product.name,
          unitId: unitId,
          unitName: selectedUnit.name,
          conversionFactor: conversionFactor,
          quantity: _quantity,
          unitPrice: _unitPrice,
          minSellingPrice: minPrice,
          maxSellingPrice: maxPrice,
        );

    Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final AsyncValue<List<ProductUnit>> extrasAsync =
        ref.watch(productUnitsProvider(widget.product.id));
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Builder(
            builder: (BuildContext context) {
              if (extrasAsync.isLoading || unitsAsync.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<ProductUnit> extras =
                  extrasAsync.value ?? const <ProductUnit>[];
              final List<Unit> allUnits =
                  unitsAsync.value ?? const <Unit>[];
              final List<Unit> available = _availableUnits(
                widget.product,
                allUnits,
                extras,
              );

              // Resolve the selected unit; fall back to the first one when
              // the stored id is no longer available.
              Unit? currentUnit;
              for (final Unit unit in available) {
                if (unit.id == _selectedUnitId) {
                  currentUnit = unit;
                  break;
                }
              }
              if (currentUnit == null && available.isNotEmpty) {
                currentUnit = available.first;
                // Defer the state change; the setter below uses setState.
                if (!_initialized) {
                  _selectedUnitId = currentUnit.id;
                  _initialized = true;
                }
              }

              final double? minPrice = currentUnit == null
                  ? null
                  : _effectiveMin(currentUnit.id, extras);
              final double? maxPrice = currentUnit == null
                  ? null
                  : _effectiveMax(currentUnit.id, extras);
              final double lineTotal = _quantity * _unitPrice;
              final bool priceValid =
                  (minPrice == null || _unitPrice >= minPrice) &&
                      (maxPrice == null || _unitPrice <= maxPrice);
              final bool canSubmit =
                  _quantity > 0 && priceValid && currentUnit != null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ---- drag handle ----
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ---- header ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            widget.product.name,
                            style: theme.textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),

                  // ---- scrollable body ----
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: <Widget>[
                        // ---- unit ----
                        Text('الوحدة',
                            style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedUnitId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<String>>[
                            for (final Unit unit in available)
                              DropdownMenuItem<String>(
                                value: unit.id,
                                child: Text(unit.name),
                              ),
                          ],
                          onChanged: (String? value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedUnitId = value;
                              _priceController.text = _formatNumber(
                                _suggestedPrice(value, extras),
                              );
                            });
                          },
                        ),

                        const SizedBox(height: 16),

                        // ---- quantity ----
                        Text('الكمية',
                            style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            IconButton.filledTonal(
                              onPressed: () {
                                final double next =
                                    _quantity > 1 ? _quantity - 1 : 1;
                                _quantityController.text =
                                    _formatNumber(next);
                                setState(() {});
                              },
                              icon: const Icon(Icons.remove),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _quantityController,
                                focusNode: _quantityFocus,
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
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 12,
                                  ),
                                ),
                                onChanged: (String _) => setState(() {}),
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: () {
                                _quantityController.text =
                                    _formatNumber(_quantity + 1);
                                setState(() {});
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ---- price ----
                        Text('سعر الوحدة',
                            style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _priceController,
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
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 12,
                            ),
                            suffixText: 'ج.م',
                            errorText: priceValid
                                ? null
                                : 'السعر خارج النطاق المسموح.',
                          ),
                          onChanged: (String _) => setState(() {}),
                        ),
                        if (minPrice != null || maxPrice != null) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            'النطاق المسموح: '
                            '${minPrice == null ? '—' : _money.format(minPrice)} '
                            '– '
                            '${maxPrice == null ? '—' : _money.format(maxPrice)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: priceValid
                                  ? scheme.onSurfaceVariant
                                  : scheme.error,
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // ---- line total ----
                        Row(
                          children: <Widget>[
                            Text('الإجمالي',
                                style: theme.textTheme.titleMedium),
                            const Spacer(),
                            Text(
                              _money.format(lineTotal),
                              style:
                                  theme.textTheme.headlineSmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                      ],
                    ),
                  ),

                  // ---- submit ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: AppButton(
                      label: 'إضافة إلى السلة',
                      icon: Icons.add_shopping_cart,
                      expanded: true,
                      size: AppButtonSize.large,
                      onPressed: canSubmit
                          ? () => _submit(
                                extras: extras,
                                availableUnits: available,
                              )
                          : null,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
