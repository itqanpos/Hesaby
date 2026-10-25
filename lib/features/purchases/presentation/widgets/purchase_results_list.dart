// lib/features/purchases/presentation/widgets/purchase_results_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../state/purchase_providers.dart';

/// Renders the filtered products for the current purchase search query.
///
/// Two presentations:
/// * **Desktop / tablet** (`compact: false`): grid of cards.
/// * **Mobile** (`compact: true`): linear list without cards.
///
/// On tap, the largest available unit is used by default (e.g. a carton
/// rather than a piece), with the unit cost derived from the base cost
/// multiplied by the unit's conversion factor. After a successful add, the
/// corresponding cart line is auto-focused so the user can type the
/// quantity immediately.
class PurchaseResultsList extends ConsumerWidget {
  const PurchaseResultsList({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Product>> resultsAsync =
        ref.watch(purchaseSearchResultsProvider);

    return resultsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (Object error, StackTrace _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'تعذّر تحميل المنتجات.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (List<Product> products) {
        if (products.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'لا نتائج مطابقة. جرّب كلمة أخرى.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (compact) {
          return _ProductList(
            products: products,
            onTap: (Product p) => _addProduct(context, ref, p),
          );
        }

        return _ProductGrid(
          products: products,
          onTap: (Product p) => _addProduct(context, ref, p),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Add product logic
  // ---------------------------------------------------------------------------

  Future<void> _addProduct(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    try {
      final List<Unit> allUnits =
          ref.read(unitsProvider).valueOrNull ?? const <Unit>[];

      // Load the product's additional unit conversions (carton, box, etc.).
      final List<ProductUnit> productUnits =
          await ref.read(productUnitsProvider(product.id).future);

      // Pick the unit with the highest conversion factor, if any.
      ProductUnit? largest;
      for (final ProductUnit pu in productUnits) {
        if (largest == null ||
            pu.conversionFactor > largest.conversionFactor) {
          largest = pu;
        }
      }

      Unit? pickedUnit;
      double pickedFactor = 1;

      if (largest != null) {
        for (final Unit u in allUnits) {
          if (u.id == largest.unitId) {
            pickedUnit = u;
            pickedFactor = largest.conversionFactor;
            break;
          }
        }
      }

      // Fall back to the product's base unit.
      if (pickedUnit == null) {
        for (final Unit u in allUnits) {
          if (u.id == product.defaultUnitId) {
            pickedUnit = u;
            break;
          }
        }
      }

      if (pickedUnit == null) {
        if (!context.mounted) return;
        _show(context, 'وحدة المنتج غير متاحة.');
        return;
      }

      // Cost per picked unit = base cost × conversion factor.
      final double pickedCost = product.costPrice * pickedFactor;

      ref.read(purchaseCartProvider.notifier).addProduct(
            product: product,
            unit: pickedUnit,
            quantity: 1,
            unitCost: pickedCost,
            conversionFactor: pickedFactor,
          );

      // Auto-focus the quantity field for the newly added line.
      ref.read(focusedCartLineProvider.notifier).state =
          '${product.id}::${pickedUnit.id}';
    } on Object {
      if (!context.mounted) return;
      _show(context, 'تعذّر إضافة المنتج.');
    }
  }

  void _show(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// ============================================================================
// Mobile — linear list (no cards)
// ============================================================================

class _ProductList extends StatelessWidget {
  const _ProductList({required this.products, required this.onTap});

  final List<Product> products;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: products.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (BuildContext context, int index) {
        final Product product = products[index];
        return InkWell(
          onTap: () => onTap(product),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((product.sku ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            product.sku!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppFormatters.money(product.costPrice),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_left, size: 18, color: scheme.outline),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// Desktop — grid of cards
// ============================================================================

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products, required this.onTap});

  final List<Product> products;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemCount: products.length,
      itemBuilder: (BuildContext context, int index) {
        final Product product = products[index];
        return _ProductGridCard(
          product: product,
          onTap: () => onTap(product),
        );
      },
    );
  }
}

class _ProductGridCard extends StatefulWidget {
  const _ProductGridCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  State<_ProductGridCard> createState() => _ProductGridCardState();
}

class _ProductGridCardState extends State<_ProductGridCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovered
                ? scheme.primaryContainer.withValues(alpha: 0.3)
                : scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? scheme.primary : scheme.outlineVariant,
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: _isHovered
                ? <BoxShadow>[
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.product.name,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                AppFormatters.money(widget.product.costPrice),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
