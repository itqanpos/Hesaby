// lib/features/purchases/presentation/state/purchase_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../domain/entities/purchase_cart.dart';
import 'purchase_cart_notifier.dart';
import 'purchase_search_notifier.dart';

/// Exposes the current purchase cart.
final NotifierProvider<PurchaseCartNotifier, PurchaseCart>
    purchaseCartProvider =
    NotifierProvider<PurchaseCartNotifier, PurchaseCart>(
  PurchaseCartNotifier.new,
);

/// Exposes the purchase search query.
final NotifierProvider<PurchaseSearchNotifier, PurchaseSearchState>
    purchaseSearchProvider =
    NotifierProvider<PurchaseSearchNotifier, PurchaseSearchState>(
  PurchaseSearchNotifier.new,
);

/// Filtered product list for the purchase search.
///
/// Watches the shared `productsProvider` (POS/sales cache) and filters by
/// the current query on name, SKU, or barcode. Returns an empty list when
/// the query is empty. Capped at 50 results to keep the list snappy.
final Provider<AsyncValue<List<Product>>> purchaseSearchResultsProvider =
    Provider<AsyncValue<List<Product>>>((ref) {
  final AsyncValue<List<Product>> productsAsync = ref.watch(productsProvider);
  final PurchaseSearchState search = ref.watch(purchaseSearchProvider);

  if (search.isEmpty) {
    return const AsyncData<List<Product>>(<Product>[]);
  }

  return productsAsync.whenData((List<Product> products) {
    final String q = search.normalizedQuery;
    final List<Product> matches = <Product>[];
    for (final Product p in products) {
      final String name = p.name.toLowerCase();
      final String sku = (p.sku ?? '').toLowerCase();
      final String barcode = (p.barcode ?? '').toLowerCase();
      if (name.contains(q) || sku.contains(q) || barcode.contains(q)) {
        matches.add(p);
        if (matches.length >= 50) {
          break;
        }
      }
    }
    return matches;
  });
});
