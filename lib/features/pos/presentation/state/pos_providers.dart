// lib/features/pos/presentation/state/pos_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../domain/entities/pos_cart.dart';
import 'pos_cart_notifier.dart';
import 'pos_search_notifier.dart';

// ============================================================================
// Primary providers
// ============================================================================

/// Provides the POS cart state.
///
/// Mutations go through `ref.read(posCartProvider.notifier)`.
final NotifierProvider<PosCartNotifier, PosCart> posCartProvider =
    NotifierProvider<PosCartNotifier, PosCart>(PosCartNotifier.new);

/// Provides the POS search query state.
///
/// Mutations go through `ref.read(posSearchProvider.notifier)`.
final NotifierProvider<PosSearchNotifier, PosSearchState> posSearchProvider =
    NotifierProvider<PosSearchNotifier, PosSearchState>(
  PosSearchNotifier.new,
);

// ============================================================================
// Search results — combines search query with the products stream
// ============================================================================

/// Provides the list of products matching the current POS search query.
///
/// The result is an `AsyncValue<List<Product>>` so the presentation layer
/// can render loading and error states coming from the products stream
/// without extra work.
///
/// Behaviour:
/// * When the query is empty (only whitespace), resolves immediately to an
///   empty list — the POS never displays the full catalogue on the search
///   screen.
/// * When the products stream is still loading, forwards `AsyncLoading`.
/// * When the products stream errored, forwards the error.
/// * Otherwise returns the first [maxResults] matches, in source order,
///   matched on name, SKU or barcode (case-insensitive, trimmed).
final Provider<AsyncValue<List<Product>>> posSearchResultsProvider =
    Provider<AsyncValue<List<Product>>>((ref) {
  const int maxResults = 20;

  final PosSearchState search = ref.watch(posSearchProvider);
  if (search.isEmpty) {
    return const AsyncData<List<Product>>(<Product>[]);
  }

  final AsyncValue<List<Product>> productsAsync =
      ref.watch(productsProvider);

  return productsAsync.whenData((List<Product> products) {
    final String query = search.normalizedQuery;
    final List<Product> matches = <Product>[];
    for (final Product product in products) {
      if (_matches(product, query)) {
        matches.add(product);
        if (matches.length >= maxResults) {
          break;
        }
      }
    }
    return matches;
  });
});

/// Whether the current search produced at least one result.
///
/// Returns `false` when the query is empty, when the products stream is
/// loading, or when it errored. Intended for empty-state handling on the
/// search screen.
final Provider<bool> posHasSearchResultsProvider = Provider<bool>((ref) {
  final AsyncValue<List<Product>> results =
      ref.watch(posSearchResultsProvider);
  return results.maybeWhen(
    data: (List<Product> products) => products.isNotEmpty,
    orElse: () => false,
  );
});

// ============================================================================
// Totals — a derived value object for the totals bar
// ============================================================================

/// Immutable snapshot of the cart totals.
///
/// Provided as a separate value object so widgets that only care about
/// totals can `watch` this provider instead of the whole cart, avoiding
/// unnecessary rebuilds when the customer changes or when a line is edited
/// without affecting the totals.
@immutable
class PosTotals extends Equatable {
  const PosTotals({
    required this.lineCount,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
  });

  /// Number of distinct lines in the cart.
  final int lineCount;

  /// Sum of line totals before discount and tax.
  final double subtotal;

  /// Header-level discount.
  final double discount;

  /// Header-level tax amount.
  final double taxAmount;

  /// Net total = subtotal − discount + taxAmount.
  final double total;

  /// Whether the cart holds no lines.
  bool get isEmpty => lineCount == 0;

  /// Whether the cart holds at least one line.
  bool get isNotEmpty => lineCount > 0;

  @override
  List<Object?> get props =>
      <Object?>[lineCount, subtotal, discount, taxAmount, total];

  @override
  String toString() =>
      'PosTotals(lineCount: $lineCount, subtotal: $subtotal, '
      'discount: $discount, taxAmount: $taxAmount, total: $total)';
}

/// Provides the current cart totals.
///
/// Rebuilds only when the cart itself changes; the underlying values are
/// recomputed by [PosCart]'s getters.
final Provider<PosTotals> posTotalsProvider = Provider<PosTotals>((ref) {
  final PosCart cart = ref.watch(posCartProvider);
  return PosTotals(
    lineCount: cart.lineCount,
    subtotal: cart.subtotal,
    discount: cart.discount,
    taxAmount: cart.taxAmount,
    total: cart.total,
  );
});

// ============================================================================
// Internal matcher
// ============================================================================

/// Returns `true` when [product] matches the normalised [query].
///
/// Matching is performed on the display name, the SKU and the barcode. The
/// query is expected to be already trimmed and lowercased.
bool _matches(Product product, String query) {
  final String name = product.name.toLowerCase();
  if (name.contains(query)) {
    return true;
  }
  final String? sku = product.sku;
  if (sku != null && sku.toLowerCase().contains(query)) {
    return true;
  }
  final String? barcode = product.barcode;
  if (barcode != null && barcode.toLowerCase().contains(query)) {
    return true;
  }
  return false;
}
