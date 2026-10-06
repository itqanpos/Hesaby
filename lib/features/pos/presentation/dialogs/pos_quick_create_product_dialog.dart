// lib/features/pos/presentation/dialogs/pos_unit_quick_add_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../state/pos_providers.dart';

/// Opens a sheet that lists every sellable unit of [product].
///
/// Tapping a unit adds **one** line at that unit's default price and closes
/// the sheet. Quantity and price are edited inside the cart, not here.
///
/// Returns `true` when a line was added, `null`/`false` otherwise.
Future<bool?> showPosUnitQuickAddSheet({
  required BuildContext context,
  required Product product,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (BuildContext ctx) => _PosUnitQuickAddSheet(product: product),
  );
}

class _PosUnitQuickAddSheet extends ConsumerWidget {
  const _PosUnitQuickAddSheet({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);
    final AsyncValue<List<ProductUnit>> extrasAsync =
        ref.watch(productUnitsProvider(product.id));

    final bool isLoading =
        unitsAsync.isLoading || extrasAsync.isLoading;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ---- Header row: title (right) + close (left) ----
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'إغلاق',
                ),
                const Spacer(),
                Text(
                  'اختر وحدة البيع',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 48),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  'المنتج: ${product.name}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _UnitsList(
                product: product,
                units: unitsAsync.valueOrNull ?? const <Unit>[],
                extras: extrasAsync.valueOrNull ?? const <ProductUnit>[],
                onAdded: () => Navigator.of(context).pop(true),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Units list
// ============================================================================

class _UnitsList extends ConsumerWidget {
  const _UnitsList({
    required this.product,
    required this.units,
    required this.extras,
    required this.onAdded,
  });

  final Product product;
  final List<Unit> units;
  final List<ProductUnit> extras;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, String> unitNames = <String, String>{
      for (final Unit u in units) u.id: u.name,
    };

    final String baseUnitName =
        unitNames[product.defaultUnitId] ?? 'وحدة';

    // ---- Build the choice list: base unit first, then extras ----
    final List<_UnitChoice> choices = <_UnitChoice>[
      _UnitChoice(
        unitId: product.defaultUnitId,
        unitName: baseUnitName,
        isBase: true,
        conversionFactor: 1,
        unitPrice: product.sellingPrice,
        minSellingPrice: product.minSellingPrice,
        maxSellingPrice: product.maxSellingPrice,
        // For the base unit, the conversion note is the product description
        // when available, or a generic "العبوة الواحدة" text otherwise.
        conversionNote: _baseUnitNote(),
        priceLabel: 'لللوحدة',
      ),
      for (final ProductUnit extra in extras)
        _UnitChoice(
          unitId: extra.unitId,
          unitName: unitNames[extra.unitId] ?? 'وحدة',
          isBase: false,
          conversionFactor: extra.conversionFactor,
          unitPrice: extra.sellingPrice ??
              product.sellingPrice * extra.conversionFactor,
          minSellingPrice: extra.minSellingPrice ??
              (product.minSellingPrice != null
                  ? product.minSellingPrice! * extra.conversionFactor
                  : null),
          maxSellingPrice: extra.maxSellingPrice ??
              (product.maxSellingPrice != null
                  ? product.maxSellingPrice! * extra.conversionFactor
                  : null),
          conversionNote: _extraUnitNote(
            extra.conversionFactor,
            baseUnitName,
          ),
          priceLabel: 'للـ${unitNames[extra.unitId] ?? 'وحدة'}',
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < choices.length; i++) ...<Widget>[
          _UnitCard(
            choice: choices[i],
            isFirst: i == 0,
            onTap: () => _addUnit(ref, choices[i]),
          ),
          if (i < choices.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  String _baseUnitNote() {
    final String? description = product.description;
    if (description != null && description.trim().isNotEmpty) {
      return 'العبوة الواحدة ${description.trim()}';
    }
    return 'الوحدة الأساسية';
  }

  static String _extraUnitNote(double factor, String baseUnitName) {
    final String factorLabel = factor == factor.roundToDouble()
        ? factor.toInt().toString()
        : factor.toStringAsFixed(2);
    return 'عدد $factorLabel $baseUnitName';
  }

  void _addUnit(WidgetRef ref, _UnitChoice choice) {
    final bool added = ref.read(posCartProvider.notifier).addLine(
          productId: product.id,
          productName: product.name,
          unitId: choice.unitId,
          unitName: choice.unitName,
          conversionFactor: choice.conversionFactor,
          quantity: 1,
          unitPrice: choice.unitPrice,
          minSellingPrice: choice.minSellingPrice,
          maxSellingPrice: choice.maxSellingPrice,
        );
    if (added) {
      onAdded();
    }
  }
}

// ============================================================================
// Unit choice (view model)
// ============================================================================

class _UnitChoice {
  const _UnitChoice({
    required this.unitId,
    required this.unitName,
    required this.isBase,
    required this.conversionFactor,
    required this.unitPrice,
    required this.minSellingPrice,
    required this.maxSellingPrice,
    required this.conversionNote,
    required this.priceLabel,
  });

  final String unitId;
  final String unitName;
  final bool isBase;
  final double conversionFactor;
  final double unitPrice;
  final double? minSellingPrice;
  final double? maxSellingPrice;
  final String conversionNote;
  final String priceLabel;
}

// ============================================================================
// Unit card — matches the reference design
// ============================================================================

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.choice,
    required this.isFirst,
    required this.onTap,
  });

  final _UnitChoice choice;
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    // The first card is styled as "selected" (radio filled, light accent
    // tint). This matches the reference design and gives the cashier an
    // obvious default target for a single tap.
    final Color cardColor = isFirst
        ? scheme.primaryContainer.withValues(alpha: 0.35)
        : scheme.surface;
    final Color borderColor = isFirst
        ? scheme.primary
        : scheme.outlineVariant;
    final double borderWidth = isFirst ? 1.5 : 1;
    final Color radioColor =
        isFirst ? scheme.primary : scheme.outlineVariant;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: borderWidth,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          child: Row(
            children: <Widget>[
              // ---- Radio indicator (leftmost in LTR, rightmost in RTL) ----
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: radioColor,
                    width: 2,
                  ),
                ),
                child: isFirst
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.primary,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // ---- Unit info (name + conversion note) ----
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      choice.unitName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      choice.conversionNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // ---- Price + unit-price label ----
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    money.format(choice.unitPrice),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isFirst ? scheme.primary : scheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    choice.priceLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
