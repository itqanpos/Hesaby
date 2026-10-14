// lib/features/pos/presentation/state/pos_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/repositories/product_repository.dart';
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
// Search results — server-side (fixes >1000 product catalogues)
// ============================================================================

/// Server-side POS search.
///
/// ## Why server-side?
///
/// The previous implementation searched the in-memory product list. That
/// list is capped at 1000 rows by the Supabase default, so any catalogue
/// larger than 1000 products silently hid the rest from the cashier.
///
/// This provider sends the query to the database via
/// `ProductRepository.listProductsPaged`, which:
/// * Filters by company, active flag, and a substring match on
///   name / SKU / barcode.
/// * Applies a stable order and a hard limit of [maxResults].
///
/// ## Debounce
///
/// Every keystroke would otherwise trigger a network round-trip. We wait
/// [_debounceDelay] before issuing the request; if the query changes
/// during that window the previous computation is disposed and only the
/// latest one runs to completion.
///
/// ## Cancellation
///
/// Riverpod 2.6.1 does not expose `ref.mounted` (that is 3.x only). We
/// track disposal with a local flag set in `ref.onDispose` instead.
final FutureProvider<List<Product>> posServerSearchProvider =
    FutureProvider<List<Product>>((ref) async {
  final PosSearchState search = ref.watch(posSearchProvider);
  if (search.isEmpty) {
    return const <Product>[];
  }

  bool isDisposed = false;
  ref.onDispose(() => isDisposed = true);

  // Debounce: collapse a burst of keystrokes into one request.
  await Future<void>.delayed(_debounceDelay);
  if (isDisposed) return const <Product>[];

  final String? companyId = ref.watch(
    companyContextProvider.select(
      (CompanyContextState s) => s.currentCompany?.id,
    ),
  );
  if (companyId == null) return const <Product>[];

  final ProductsPageResult page = await ref
      .read(productRepositoryProvider)
      .listProductsPaged(
        companyId: companyId,
        offset: 0,
        limit: _maxResults,
        searchQuery: search.normalizedQuery,
        isActive: true,
        sortField: ProductSortField.name,
        sortAscending: true,
      );

  if (isDisposed) return const <Product>[];
  return page.items;
});

/// Debounce window for the POS search.
///
/// Long enough to collapse normal typing, short enough that a barcode
/// scan still feels immediate.
const Duration _debounceDelay = Duration(milliseconds: 200);

/// Hard cap on the number of POS search results returned to the UI.
const int _maxResults = 20;

/// Provides the list of products matching the current POS search query.
///
/// Delegates to [posServerSearchProvider]. Kept as a separate provider so
/// the presentation layer does not need to change.
final Provider<AsyncValue<List<Product>>> posSearchResultsProvider =
    Provider<AsyncValue<List<Product>>>((ref) {
  return ref.watch(posServerSearchProvider);
});

/// Whether the current search produced at least one result.
///
/// Returns `false` when the query is empty, while the request is in
/// flight, or when it errored. Intended for empty-state handling on the
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
