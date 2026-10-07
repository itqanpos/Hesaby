// lib/features/pos/presentation/widgets/pos_product_result_tile.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../inventory/domain/entities/inventory_balance.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../products/domain/entities/product.dart';

/// A single search-result row in the POS.
///
/// Layout (right-to-left in RTL):
/// * Product name (title), with an optional SKU / barcode subtitle.
/// * Stock badge (only when known): "متاح: 15", "آخر 3", or "غير متوفر".
/// * Selling price in the company currency, for the **default unit**.
/// * Default unit name.
///
/// Tapping the row opens the unit-selection sheet
/// (`showPosUnitQuickAddSheet`), where the cashier picks the unit to add.
/// Quantity and unit price are then edited inside the cart itself.
class PosProductResultTile extends ConsumerWidget {
  const PosProductResultTile({
    super.key,
    required this.product,
    required this.unitName,
    required this.onTap,
  });

  /// The product to render.
  final Product product;

  /// Display name of the product's default unit (already resolved by the
  /// caller). Pass `null` when the unit could not be resolved.
  final String? unitName;

  /// Called when the cashier taps the row.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final NumberFormat number = NumberFormat.decimalPattern('en_US');

    // ---- Read the current stock for the selected branch ----
    final String? branchId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentBranch?.id,
      ),
    );

    double? available;
    if (branchId != null) {
      final AsyncValue<List<InventoryBalance>> balancesAsync = ref.watch(
        inventoryBalancesProvider(branchId),
      );
      available = balancesAsync.maybeWhen(
        data: (List<InventoryBalance> balances) {
          for (final InventoryBalance balance in balances) {
            if (balance.productId == product.id) {
              return balance.quantityOnHand;
            }
          }
          return 0.0;
        },
        orElse: () => null,
      );
    }

    final bool outOfStock = available != null && available <= 0;
    final bool lowStock =
        available != null && available > 0 && available <= 3;
    final String? sku = product.sku;
    final String? barcode = product.barcode;

    return Material(
      color: scheme.surface,
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // -----------------------------------------------------------------
              // Main info
              // -----------------------------------------------------------------
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      product.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sku != null || barcode != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(sku: sku, barcode: barcode),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        if (unitName != null) ...<Widget>[
                          Text(
                            unitName!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (available != null)
                          _StockBadge(
                            available: available,
                            outOfStock: outOfStock,
                            lowStock: lowStock,
                            number: number,
                            theme: theme,
                            scheme: scheme,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // -----------------------------------------------------------------
              // Price + arrow
              // -----------------------------------------------------------------
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    money.format(product.sellingPrice),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    Icons.chevron_left,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the small subtitle combining SKU and barcode when present.
  static String _subtitle({
    required String? sku,
    required String? barcode,
  }) {
    final List<String> parts = <String>[];
    if (sku != null && sku.trim().isNotEmpty) {
      parts.add('SKU: $sku');
    }
    if (barcode != null && barcode.trim().isNotEmpty) {
      parts.add(barcode);
    }
    return parts.join('  •  ');
  }
}

// ============================================================================
// Stock badge
// ============================================================================

class _StockBadge extends StatelessWidget {
  const _StockBadge({
    required this.available,
    required this.outOfStock,
    required this.lowStock,
    required this.number,
    required this.theme,
    required this.scheme,
  });

  final double available;
  final bool outOfStock;
  final bool lowStock;
  final NumberFormat number;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (true) {
      _ when outOfStock => ('غير متوفر', scheme.error),
      _ when lowStock => ('آخر ${number.format(available)}', scheme.tertiary),
      _ => ('متاح: ${number.format(available)}', scheme.onSurfaceVariant),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.inventory_2_outlined, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
