// lib/features/products/presentation/providers/product_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/product_remote_datasource.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_unit.dart';
import '../../domain/repositories/product_repository.dart';

// ============================================================================
// Repository
// ============================================================================

/// The application's product repository.
final Provider<ProductRepository> productRepositoryProvider =
    Provider<ProductRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return ProductRepositoryImpl(ProductRemoteDataSource(client));
});

// ============================================================================
// Legacy list provider (used by POS, sales dialogs, etc.)
// ============================================================================

/// Provides the *complete* list of products for the currently selected
/// company. Kept for consumers that genuinely need every product in
/// memory (POS scanner fallback, sale form lookup).
///
/// The products page no longer uses this provider; it uses the paginated
/// stack below.
class ProductsNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <Product>[];
    }

    return ref.read(productRepositoryProvider).listProducts(companyId);
  }

  Future<Product> createProduct({
    required String name,
    required String defaultUnitId,
    required double costPrice,
    required double sellingPrice,
    String? categoryId,
    String? sku,
    String? barcode,
    String? description,
    double? minSellingPrice,
    double? taxRate,
  }) async {
    final String companyId = _requireCurrentCompanyId();

    final Product created =
        await ref.read(productRepositoryProvider).createProduct(
              companyId: companyId,
              name: name,
              defaultUnitId: defaultUnitId,
              costPrice: costPrice,
              sellingPrice: sellingPrice,
              categoryId: categoryId,
              sku: sku,
              barcode: barcode,
              description: description,
              minSellingPrice: minSellingPrice,
              taxRate: taxRate,
            );

    await _reload();
    ref.invalidate(productCountsProvider);
    ref.invalidate(pagedProductsProvider);
    return created;
  }

  Future<Product> updateProduct({
    required String productId,
    String? name,
    String? defaultUnitId,
    String? categoryId,
    bool clearCategory = false,
    String? sku,
    bool clearSku = false,
    String? barcode,
    bool clearBarcode = false,
    String? description,
    bool clearDescription = false,
    double? costPrice,
    double? sellingPrice,
    double? minSellingPrice,
    bool clearMinSellingPrice = false,
    double? taxRate,
    bool clearTaxRate = false,
    bool? isActive,
  }) async {
    final Product updated =
        await ref.read(productRepositoryProvider).updateProduct(
              productId: productId,
              name: name,
              defaultUnitId: defaultUnitId,
              categoryId: categoryId,
              clearCategory: clearCategory,
              sku: sku,
              clearSku: clearSku,
              barcode: barcode,
              clearBarcode: clearBarcode,
              description: description,
              clearDescription: clearDescription,
              costPrice: costPrice,
              sellingPrice: sellingPrice,
              minSellingPrice: minSellingPrice,
              clearMinSellingPrice: clearMinSellingPrice,
              taxRate: taxRate,
              clearTaxRate: clearTaxRate,
              isActive: isActive,
            );

    await _reload();
    ref.invalidate(productCountsProvider);
    ref.invalidate(pagedProductsProvider);
    return updated;
  }

  Future<void> deleteProduct(String productId) async {
    await ref.read(productRepositoryProvider).deleteProduct(productId);
    await _reload();
    ref.invalidate(productCountsProvider);
    ref.invalidate(pagedProductsProvider);
  }

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const ProductException(
        type: ProductFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }
    return companyId;
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<ProductsNotifier, List<Product>> productsProvider =
    AsyncNotifierProvider<ProductsNotifier, List<Product>>(ProductsNotifier.new);

// ============================================================================
// Global counts (KPI)
// ============================================================================

/// Provides total / active / inactive product counts for the current
/// company. Refreshed whenever a mutation invalidates it.
final FutureProvider<ProductCounts> productCountsProvider =
    FutureProvider<ProductCounts>((ref) async {
  final String? companyId = ref.watch(
    companyContextProvider.select(
      (CompanyContextState s) => s.currentCompany?.id,
    ),
  );
  if (companyId == null) {
    return const ProductCounts.zero();
  }
  return ref.read(productRepositoryProvider).countProducts(companyId);
});

// ============================================================================
// Filter state
// ============================================================================

/// Immutable set of filter / sort options for the paged product list.
@immutable
class ProductsFilter extends Equatable {
  const ProductsFilter({
    this.searchQuery = '',
    this.categoryId,
    this.isActive,
    this.sortField = ProductSortField.name,
    this.sortAscending = true,
  });

  final String searchQuery;
  final String? categoryId;

  /// `null` = both, `true` = active only, `false` = inactive only.
  final bool? isActive;

  final ProductSortField sortField;
  final bool sortAscending;

  ProductsFilter copyWith({
    String? searchQuery,
    String? categoryId,
    bool clearCategory = false,
    bool? isActive,
    bool clearIsActive = false,
    ProductSortField? sortField,
    bool? sortAscending,
  }) {
    return ProductsFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      isActive: clearIsActive ? null : (isActive ?? this.isActive),
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[searchQuery, categoryId, isActive, sortField, sortAscending];
}

/// Notifier for [ProductsFilter]. Each setter triggers a rebuild of the
/// paged list; the caller does not need to invalidate anything manually.
class ProductsFilterNotifier extends Notifier<ProductsFilter> {
  @override
  ProductsFilter build() => const ProductsFilter();

  void setSearch(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setCategory(String? categoryId) {
    state = categoryId == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(categoryId: categoryId);
  }

  void setStatus(bool? isActive) {
    state = isActive == null
        ? state.copyWith(clearIsActive: true)
        : state.copyWith(isActive: isActive);
  }

  void setSort(ProductSortField field, {required bool ascending}) {
    state = state.copyWith(sortField: field, sortAscending: ascending);
  }

  void clearAll() {
    state = const ProductsFilter();
  }
}

final NotifierProvider<ProductsFilterNotifier, ProductsFilter>
    productsFilterProvider =
    NotifierProvider<ProductsFilterNotifier, ProductsFilter>(
  ProductsFilterNotifier.new,
);

// ============================================================================
// Paged list state
// ============================================================================

/// State of the paginated products list.
@immutable
class PagedProducts extends Equatable {
  const PagedProducts({
    required this.items,
    required this.hasMore,
    required this.isLoadingMore,
  });

  const PagedProducts.initial()
      : items = const <Product>[],
        hasMore = true,
        isLoadingMore = false;

  final List<Product> items;
  final bool hasMore;
  final bool isLoadingMore;

  PagedProducts copyWith({
    List<Product>? items,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return PagedProducts(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => <Object?>[items, hasMore, isLoadingMore];
}

/// Paginated products list.
///
/// Rebuilds from offset 0 whenever the current company or the filter
/// changes. [loadMore] appends the next page.
class PagedProductsNotifier extends AsyncNotifier<PagedProducts> {
  static const int _pageSize = 20;

  bool _isDisposed = false;
  int _nextOffset = 0;
  bool _isFetchingMore = false;

  @override
  Future<PagedProducts> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);

    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    final ProductsFilter filter = ref.watch(productsFilterProvider);

    if (companyId == null) {
      _nextOffset = 0;
      return const PagedProducts.initial();
    }

    final ProductsPageResult page =
        await ref.read(productRepositoryProvider).listProductsPaged(
              companyId: companyId,
              offset: 0,
              limit: _pageSize,
              categoryId: filter.categoryId,
              isActive: filter.isActive,
              searchQuery: filter.searchQuery,
              sortField: filter.sortField,
              sortAscending: filter.sortAscending,
            );

    _nextOffset = page.items.length;

    return PagedProducts(
      items: page.items,
      hasMore: page.hasMore,
      isLoadingMore: false,
    );
  }

  /// Fetches and appends the next page, if any.
  Future<void> loadMore() async {
    if (_isDisposed || _isFetchingMore) {
      return;
    }
    final PagedProducts? current = state.valueOrNull;
    if (current == null || !current.hasMore) {
      return;
    }

    _isFetchingMore = true;
    state = AsyncData<PagedProducts>(
      current.copyWith(isLoadingMore: true),
    );

    final String? companyId = ref.read(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      _isFetchingMore = false;
      if (!_isDisposed) {
        state = AsyncData<PagedProducts>(
          current.copyWith(isLoadingMore: false, hasMore: false),
        );
      }
      return;
    }

    final ProductsFilter filter = ref.read(productsFilterProvider);

    try {
      final ProductsPageResult page =
          await ref.read(productRepositoryProvider).listProductsPaged(
                companyId: companyId,
                offset: _nextOffset,
                limit: _pageSize,
                categoryId: filter.categoryId,
                isActive: filter.isActive,
                searchQuery: filter.searchQuery,
                sortField: filter.sortField,
                sortAscending: filter.sortAscending,
              );

      if (_isDisposed) {
        return;
      }

      _nextOffset += page.items.length;

      state = AsyncData<PagedProducts>(
        PagedProducts(
          items: <Product>[...current.items, ...page.items],
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (_isDisposed) {
        return;
      }
      // Keep the already-loaded items; surface the error only if the list
      // is still empty.
      if (current.items.isEmpty) {
        state = AsyncError<PagedProducts>(error, stackTrace);
      } else {
        state = AsyncData<PagedProducts>(
          current.copyWith(isLoadingMore: false, hasMore: false),
        );
      }
    } finally {
      _isFetchingMore = false;
    }
  }

  /// Re-fetches from offset 0 without changing the filter.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<PagedProductsNotifier, PagedProducts>
    pagedProductsProvider =
    AsyncNotifierProvider<PagedProductsNotifier, PagedProducts>(
  PagedProductsNotifier.new,
);

// ============================================================================
// Product units (unchanged)
// ============================================================================

class ProductUnitsNotifier
    extends FamilyAsyncNotifier<List<ProductUnit>, String> {
  @override
  Future<List<ProductUnit>> build(String productId) async {
    return ref.read(productRepositoryProvider).listProductUnits(productId);
  }

  Future<ProductUnit> addProductUnit({
    required String unitId,
    required double conversionFactor,
  }) async {
    final String productId = arg;

    final ProductUnit created = await ref
        .read(productRepositoryProvider)
        .addProductUnit(
          productId: productId,
          unitId: unitId,
          conversionFactor: conversionFactor,
        );

    await _reload();
    return created;
  }

  Future<ProductUnit> updateProductUnit({
    required String productUnitId,
    required double conversionFactor,
  }) async {
    final ProductUnit updated =
        await ref.read(productRepositoryProvider).updateProductUnit(
              productUnitId: productUnitId,
              conversionFactor: conversionFactor,
            );

    await _reload();
    return updated;
  }

  Future<void> deleteProductUnit(String productUnitId) async {
    await ref.read(productRepositoryProvider).deleteProductUnit(productUnitId);
    await _reload();
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final productUnitsProvider = AsyncNotifierProvider.family<
    ProductUnitsNotifier, List<ProductUnit>, String>(ProductUnitsNotifier.new);
