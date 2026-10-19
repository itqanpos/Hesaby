// lib/features/pos/presentation/state/pos_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../domain/entities/pos_cart.dart';
import '../../domain/services/pos_tax_calculator.dart';
import 'pos_cart_notifier.dart';
import 'pos_search_notifier.dart';

// ============================================================================
// Primary providers
// ============================================================================

final NotifierProvider<PosCartNotifier, PosCart> posCartProvider =
    NotifierProvider<PosCartNotifier, PosCart>(PosCartNotifier.new);

final NotifierProvider<PosSearchNotifier, PosSearchState> posSearchProvider =
    NotifierProvider<PosSearchNotifier, PosSearchState>(
  PosSearchNotifier.new,
);

/// ⬇️ جديد: يتتبع المنتج الذي تمت إضافته للتو لتوجيه التركيز إلى حقل الكمية.
/// القيمة هي `key` الخاص بالسطر (productId::unitId).
final StateProvider<String?> focusedCartLineProvider =
    StateProvider<String?>((ref) => null);

// ============================================================================
// Search results — server-side
// ============================================================================

final FutureProvider<List<Product>> posServerSearchProvider =
    FutureProvider<List<Product>>((ref) async {
  final PosSearchState search = ref.watch(posSearchProvider);
  if (search.isEmpty) {
    return const <Product>[];
  }

  bool isDisposed = false;
  ref.onDispose(() => isDisposed = true);

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

const Duration _debounceDelay = Duration(milliseconds: 200);
const int _maxResults = 20;

final Provider<AsyncValue<List<Product>>> posSearchResultsProvider =
    Provider<AsyncValue<List<Product>>>((ref) {
  return ref.watch(posServerSearchProvider);
});

final Provider<bool> posHasSearchResultsProvider = Provider<bool>((ref) {
  final AsyncValue<List<Product>> results =
      ref.watch(posSearchResultsProvider);
  return results.maybeWhen(
    data: (List<Product> products) => products.isNotEmpty,
    orElse: () => false,
  );
});

// ============================================================================
// Totals
// ============================================================================

@immutable
class PosTotals extends Equatable {
  const PosTotals({
    required this.lineCount,
    required this.subtotal,
    required this.discount,
    required this.taxAmount,
    required this.total,
  });

  final int lineCount;
  final double subtotal;
  final double discount;
  final double taxAmount;
  final double total;

  bool get isEmpty => lineCount == 0;
  bool get isNotEmpty => lineCount > 0;

  @override
  List<Object?> get props =>
      <Object?>[lineCount, subtotal, discount, taxAmount, total];

  @override
  String toString() =>
      'PosTotals(lineCount: $lineCount, subtotal: $subtotal, '
      'discount: $discount, taxAmount: $taxAmount, total: $total)';
}

final Provider<PosTotals> posTotalsProvider = Provider<PosTotals>((ref) {
  final PosCart cart = ref.watch(posCartProvider);
  final double defaultTaxRate = ref.watch(defaultTaxRateProvider);

  final double afterDiscount = cart.subtotal - cart.discount;
  final double tax = PosTaxCalculator.taxFor(
    afterDiscount: afterDiscount,
    manualTax: cart.taxAmount,
    defaultTaxRate: defaultTaxRate,
  );

  return PosTotals(
    lineCount: cart.lineCount,
    subtotal: cart.subtotal,
    discount: cart.discount,
    taxAmount: tax,
    total: PosTaxCalculator.totalFor(afterDiscount: afterDiscount, tax: tax),
  );
});
