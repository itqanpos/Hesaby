// lib/features/products/presentation/providers/product_providers.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;
import 'package:uuid/uuid.dart';

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../../data/local/app_database.dart';
// ✅ استيراد الـ DAO الخاص بالمنتجات للوصول إلى toCompanion و toJsonPayload
import '../../../../data/local/daos/products_dao.dart';

// النظام القديم (نستخدمه مؤقتاً للوحدات فقط)
import '../../data/datasources/product_remote_datasource.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_unit.dart';
import '../../domain/repositories/product_repository.dart';

// ============================================================================
// Repository (Legacy - for Product Units only)
// ============================================================================

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
// Products (Offline-First via Drift)
// ============================================================================

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

    final AppDatabase db = ref.watch(appDatabaseProvider);

    // 1. الاستماع المستمر للتغييرات في Drift
    final StreamSubscription<List<Product>> sub =
        db.productsDao.watchProducts(companyId: companyId).listen((List<Product> data) {
      state = AsyncData(data);
    });

    ref.onDispose(() => sub.cancel());

    // 2. إرجاع القيمة الأولى لكي تظهر الشاشة فوراً
    return db.productsDao.watchProducts(companyId: companyId).first;
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
    final DateTime now = DateTime.now();
    final String newId = const Uuid().v4();

    final Product newProduct = Product(
      id: newId,
      companyId: companyId,
      defaultUnitId: defaultUnitId,
      name: name,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      categoryId: categoryId,
      sku: sku,
      barcode: barcode,
      description: description,
      minSellingPrice: minSellingPrice,
      taxRate: taxRate,
    );

    final AppDatabase db = ref.read(appDatabaseProvider);
    
    // الكتابة في Drift + Outbox
    await db.productsDao.createProduct(
      product: newProduct.toCompanion(),
      productPayload: newProduct.toJsonPayload(),
    );

    ref.invalidate(productCountsProvider);
    // لا حاجة لـ _reload()، الـ Stream سيتكفل بتحديث الواجهة
    return newProduct;
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
    final AppDatabase db = ref.read(appDatabaseProvider);
    
    final Product? existing = await db.productsDao.getProductById(productId);
    if (existing == null) {
      throw const ProductException(
        type: ProductFailureType.notFound,
        cause: 'Product not found locally.',
      );
    }

    final Product updated = existing.copyWith(
      name: name,
      defaultUnitId: defaultUnitId,
      categoryId: clearCategory ? null : (categoryId ?? existing.categoryId),
      sku: clearSku ? null : (sku ?? existing.sku),
      barcode: clearBarcode ? null : (barcode ?? existing.barcode),
      description: clearDescription ? null : (description ?? existing.description),
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      minSellingPrice: clearMinSellingPrice ? null : (minSellingPrice ?? existing.minSellingPrice),
      taxRate: clearTaxRate ? null : (taxRate ?? existing.taxRate),
      isActive: isActive,
      updatedAt: DateTime.now(),
    );

    await db.productsDao.updateProduct(
      product: updated.toCompanion(),
      productPayload: updated.toJsonPayload(),
    );

    ref.invalidate(productCountsProvider);
    return updated;
  }

  Future<void> deleteProduct(String productId) async {
    final String companyId = _requireCurrentCompanyId();
    final AppDatabase db = ref.read(appDatabaseProvider);
    
    await db.productsDao.deleteProduct(
      productId: productId,
      companyId: companyId,
    );
    
    ref.invalidate(productCountsProvider);
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
}

final AsyncNotifierProvider<ProductsNotifier, List<Product>> productsProvider =
    AsyncNotifierProvider<ProductsNotifier, List<Product>>(ProductsNotifier.new);

// ============================================================================
// Global counts (KPI) - Local Drift
// ============================================================================

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

  final AppDatabase db = ref.watch(appDatabaseProvider);

  // حساب الأعداد محلياً باستخدام Drift
  final int total = await db.productsDao.count(companyId: companyId);
  final int active = await db.productsDao.count(companyId: companyId, isActive: true);
  final int inactive = await db.productsDao.count(companyId: companyId, isActive: false);

  return ProductCounts(
    total: total,
    active: active,
    inactive: inactive,
  );
});

// ============================================================================
// Filter state (Unchanged)
// ============================================================================

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

class ProductsFilterNotifier extends Notifier<ProductsFilter> {
  @override
  ProductsFilter build() => const ProductsFilter();

  void setSearch(String query) => state = state.copyWith(searchQuery: query);
  void setCategory(String? categoryId) => state = categoryId == null
      ? state.copyWith(clearCategory: true)
      : state.copyWith(categoryId: categoryId);
  void setStatus(bool? isActive) => state = isActive == null
      ? state.copyWith(clearIsActive: true)
      : state.copyWith(isActive: isActive);
  void setSort(ProductSortField field, {required bool ascending}) =>
      state = state.copyWith(sortField: field, sortAscending: ascending);
  void clearAll() => state = const ProductsFilter();
}

final NotifierProvider<ProductsFilterNotifier, ProductsFilter>
    productsFilterProvider =
    NotifierProvider<ProductsFilterNotifier, ProductsFilter>(
  ProductsFilterNotifier.new,
);

// ============================================================================
// Paged list state (Offline-First via Drift)
// ============================================================================

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
    final AppDatabase db = ref.watch(appDatabaseProvider);

    if (companyId == null) {
      _nextOffset = 0;
      return const PagedProducts.initial();
    }

    // جلب الصفحة الأولى من Drift
    final List<Product> items = await db.productsDao
        .watchProducts(
          companyId: companyId,
          categoryId: filter.categoryId,
          searchQuery: filter.searchQuery,
          limit: _pageSize,
          offset: 0,
        )
        .first;

    _nextOffset = items.length;

    return PagedProducts(
      items: items,
      hasMore: items.length == _pageSize,
      isLoadingMore: false,
    );
  }

  Future<void> loadMore() async {
    if (_isDisposed || _isFetchingMore) return;
    final PagedProducts? current = state.valueOrNull;
    if (current == null || !current.hasMore) return;

    _isFetchingMore = true;
    state = AsyncData<PagedProducts>(current.copyWith(isLoadingMore: true));

    final String? companyId = ref.read(
      companyContextProvider.select((CompanyContextState s) => s.currentCompany?.id),
    );
    if (companyId == null) {
      _isFetchingMore = false;
      if (!_isDisposed) {
        state = AsyncData<PagedProducts>(current.copyWith(isLoadingMore: false, hasMore: false));
      }
      return;
    }

    final ProductsFilter filter = ref.read(productsFilterProvider);
    final AppDatabase db = ref.read(appDatabaseProvider);

    try {
      final List<Product> items = await db.productsDao
          .watchProducts(
            companyId: companyId,
            categoryId: filter.categoryId,
            searchQuery: filter.searchQuery,
            limit: _pageSize,
            offset: _nextOffset,
          )
          .first;

      if (_isDisposed) return;

      _nextOffset += items.length;

      state = AsyncData<PagedProducts>(
        PagedProducts(
          items: <Product>[...current.items, ...items],
          hasMore: items.length == _pageSize,
          isLoadingMore: false,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (_isDisposed) return;
      if (current.items.isEmpty) {
        state = AsyncError<PagedProducts>(error, stackTrace);
      } else {
        state = AsyncData<PagedProducts>(current.copyWith(isLoadingMore: false, hasMore: false));
      }
    } finally {
      _isFetchingMore = false;
    }
  }

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
// Product units (Legacy - Supabase)
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
