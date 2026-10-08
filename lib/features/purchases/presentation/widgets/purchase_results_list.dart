// lib/features/purchases/presentation/widgets/purchase_results_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../state/purchase_providers.dart';
import 'purchase_product_result_tile.dart';

/// Renders the filtered products for the current purchase search query.
///
/// Handles three states: loading, error, and empty. In the empty case a
/// hint is shown instead of an empty list.
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

  void _addProduct(BuildContext context, WidgetRef ref, Product product) {
    final AsyncValue<List<Unit>> unitsAsync = ref.read(unitsProvider);
    final List<Unit> units = unitsAsync.valueOrNull ?? const <Unit>[];

    Unit? defaultUnit;
    for (final Unit u in units) {
      if (u.id == product.defaultUnitId) {
        defaultUnit = u;
        break;
      }
    }

    if (defaultUnit == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('وحدة المنتج غير متاحة.'),
          ),
        );
      return;
    }

    ref.read(purchaseCartProvider.notifier).addProduct(
          product: product,
          unit: defaultUnit,
        );
  }
}
