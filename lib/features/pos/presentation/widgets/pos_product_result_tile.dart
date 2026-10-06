// lib/features/pos/presentation/widgets/pos_product_result_tile.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../inventory/domain/entities/inventory_balance.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../dialogs/pos_unit_quick_add_sheet.dart';

/// A single search-result tile in the POS.
///
/// Layout:
/// * Product name (title), with an optional SKU / barcode subtitle.
/// * One row per available unit:
///   `unit name | price | stock badge | [+]`
///
/// Tapping a unit row (or its `[+]` button) opens the compact
/// `showPosUnitQuickAddSheet` dialog, where the cashier confirms the
/// quantity and price. The bottom sheet that used to occupy 75% of the
/// screen has been removed.
///
/// No product images are used anywhere in this widget.
class PosProductResultTile extends ConsumerWidget {
  const PosProductResultTile({
    super.key,
    required this.product,
    required this.onAdded,
  });

  /// The product to render.
  final Product product;

  /// Called after a unit was successfully added to the cart.
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    // ---- Stock in base units, for the current branch ----
    final String? branchId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentBranch?.id,
      ),
    );
    double? baseStock;
    if (branchId != null) {
      final AsyncValue<List<InventoryBalance>> balancesAsync =
          ref.watch(inventoryBalancesProvider(branchId));
      baseStock = balancesAsync.maybeWhen(
        data: (List<InventoryBalance> balances) {
          for (final InventoryBalance b in balances) {
            if (b.productId == product.id) {
              return b.quantityOnHand;
            }
          }
          return 0.0;
        },
        orElse: () => null,
      );
    }

    // ---- Unit names ----
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);
    final Map<String, String> unitNames = unitsAsync.maybeWhen(
      data: (List<Unit> units) => <String, String>{
        for (final Unit u in units) u.id: u.name,
      },
      orElse: () => const <String, String>{},
    );

    // ---- Extra (non-base) units ----
    final AsyncValue<List<ProductUnit>> extrasAsync =
        ref.watch(productUnitsProvider(product.id));
    final List<ProductUnit> extras =
        extrasAsync.valueOrNull ?? const <ProductUnit>[];

    // ---- Build the choice list: base unit first, then extras ----
    final List<_UnitChoice> choices = <_UnitChoice>[
      _UnitChoice(
        unitId: product.defaultUnitId,
        unitName: unitNames[product.defaultUnitId] ?? 'الوحدة',
        conversionFactor: 1,
        unitPrice: product.sellingPrice,
        minSellingPrice: product.minSellingPrice,
        maxSellingPrice: product.maxSellingPrice,
        availableStock: baseStock,
      ),
      for (final ProductUnit extra in extras)
        _UnitChoice(
          unitId: extra.unitId,
          unitName: unitNames[extra.unitId] ?? 'وحدة',
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
          availableStock: baseStock != null
              ? baseStock / extra.conversionFactor
              : null,
        ),
    ];

    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // ---- Header ----
            Text(
              product.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (_hasSubtitle(product)) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                _subtitle(product),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            // ---- Unit rows ----
            for (final _UnitChoice c in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _UnitRow(
                  choice: c,
                  onTap: () => _openQuickAdd(context, ref, c),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  Future<void> _openQuickAdd(
    BuildContext context,
    WidgetRef ref,
    _UnitChoice choice,
  ) async {
    final bool? added = await showPosUnitQuickAddSheet(
      context: context,
      product: product,
      unitId: choice.unitId,
      unitName: choice.unitName,
      conversionFactor: choice.conversionFactor,
      defaultPrice: choice.unitPrice,
      minSellingPrice: choice.minSellingPrice,
      maxSellingPrice: choice.maxSellingPrice,
      availableStock: choice.availableStock,
    );

    if (added == true) {
      onAdded();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static bool _hasSubtitle(Product product) {
    final String? sku = product.sku;
    final String? barcode = product.barcode;
    return (sku != null && sku.trim().isNotEmpty) ||
        (barcode != null && barcode.trim().isNotEmpty);
  }

  static String _subtitle(Product product) {
    final List<String> parts = <String>[];
    if (product.sku != null && product.sku!.trim().isNotEmpty) {
      parts.add('SKU: ${product.sku}');
    }
    if (product.barcode != null && product.barcode!.trim().isNotEmpty) {
      parts.add(product.barcode!);
    }
    return parts.join('  •  ');
  }
}

// ============================================================================
// Unit choice (view model)
// ============================================================================

class _UnitChoice {
  const _UnitChoice({
    required this.unitId,
    required this.unitName,
    required this.conversionFactor,
    required this.unitPrice,
    required this.minSellingPrice,
    required this.maxSellingPrice,
    required this.availableStock,
  });

  final String unitId;
  final String unitName;
  final double conversionFactor;
  final double unitPrice;
  final double? minSellingPrice;
  final double? maxSellingPrice;
  final double? availableStock;

  bool get isOutOfStock =>
      availableStock != null && availableStock! <= 0;
  bool get isLowStock =>
      availableStock != null && availableStock! > 0 && availableStock! <= 3;
}

// ============================================================================
// Unit row
// ============================================================================

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.choice, required this.onTap});

  final _UnitChoice choice;
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
    final NumberFormat number = NumberFormat.decimalPattern('en_US');

    final bool out = choice.isOutOfStock;
    final Color stockColor = out
        ? scheme.error
        : (choice.isLowStock ? scheme.tertiary : scheme.onSurfaceVariant);

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: out ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: <Widget>[
              // Unit name
              Expanded(
                flex: 3,
                child: Text(
                  choice.unitName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Price
              Expanded(
                flex: 3,
                child: Text(
                  money.format(choice.unitPrice),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Stock
              Expanded(
                flex: 3,
                child: Text(
                  choice.availableStock == null
                      ? '—'
                      : 'متاح ${number.format(choice.availableStock)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: stockColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              // [+] button
              SizedBox(
                width: 36,
                height: 36,
                child: Material(
                  color: out
                      ? scheme.surfaceContainerHighest
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: out ? null : onTap,
                    child: Icon(
                      Icons.add,
                      size: 18,
                      color: out
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
