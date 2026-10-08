// lib/features/purchases/presentation/widgets/purchase_results_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../state/purchase_providers.dart';
import 'purchase_product_result_tile.dart';

/// Renders the filtered products for the current purchase search query.
///
/// When the user taps a product, the largest available unit is used by
/// default (e.g. a carton rather than a piece), with the unit cost derived
/// from the base cost times the unit's conversion factor.
class PurchaseResultsList extends ConsumerWidget {
  const PurchaseResultsList({super.key});

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

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (BuildContext itemContext, int index) {
            final Product product = products[index];
            return PurchaseProductResultTile(
              product: product,
              onTap: () => _addProduct(context, ref, product),
            );
          },
        );
      },
    );
  }

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
        if (largest == null || pu.conversionFactor > largest.conversionFactor) {
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('وحدة المنتج غير متاحة.')),
          );
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
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تعذّر إضافة المنتج.')),
        );
    }
  }
}
