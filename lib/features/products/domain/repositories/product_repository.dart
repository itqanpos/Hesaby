// lib/features/products/domain/repositories/product_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/product.dart';
import '../entities/product_unit.dart';

// ============================================================================
// Failure types (unchanged from previous version)
// ============================================================================

enum ProductFailureType {
  network,
  unauthorized,
  notFound,
  skuConflict,
  barcodeConflict,
  categoryNotFound,
  unitNotFound,
  inUse,
  invalidResponse,
  unknown,
}

@immutable
class ProductException extends Equatable implements Exception {
  const ProductException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final ProductFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'ProductException(type: ${type.name})';
}

// ============================================================================
// Pagination / sort helpers
// ============================================================================

/// Sort field for paginated product listings.
enum ProductSortField {
  name('name'),
  sellingPrice('selling_price'),
  costPrice('cost_price'),
  createdAt('created_at');

  const ProductSortField(this.column);

  /// The database column name.
  final String column;
}

/// A single page of products.
@immutable
class ProductsPageResult extends Equatable {
  const ProductsPageResult({
    required this.items,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  /// Items in this page.
  final List<Product> items;

  /// Offset used to fetch this page.
  final int offset;

  /// Maximum number of items requested.
  final int limit;

  /// Whether more items are likely available after this page.
  ///
  /// Computed as `items.length == limit` — a heuristic that avoids an
  /// extra count query. It may be `true` when the page happens to end
  /// exactly on the last item; the next request then returns an empty
  /// page and closes the loop.
  final bool hasMore;

  @override
  List<Object?> get props => <Object?>[items, offset, limit, hasMore];
}

/// Total counts per stock status, used by the KPI header.
@immutable
class ProductCounts extends Equatable {
  const ProductCounts({
    required this.total,
    required this.active,
    required this.inactive,
  });

  const ProductCounts.zero()
      : total = 0,
        active = 0,
        inactive = 0;

  final int total;
  final int active;
  final int inactive;

  @override
  List<Object?> get props => <Object?>[total, active, inactive];
}

// ============================================================================
// Repository interface
// ============================================================================

abstract interface class ProductRepository {
  // ---------------------------------------------------------------------------
  // Products — legacy (used by POS and other features)
  // ---------------------------------------------------------------------------

  /// Returns every product of [companyId] visible to the current user.
  ///
  /// Kept for existing consumers (POS, sales dialogs). New UI surfaces
  /// should prefer [listProductsPaged].
  Future<List<Product>> listProducts(
    String companyId, {
    bool includeInactive = false,
    String? categoryId,
  });

  /// Returns a single product by id.
  Future<Product> getProduct(String productId);

  // ---------------------------------------------------------------------------
  // Products — paginated / filtered / sorted
  // ---------------------------------------------------------------------------

  /// Returns one page of products, with optional filter, search and sort.
  ///
  /// [searchQuery], when provided, matches name, SKU or barcode using a
  /// case-insensitive substring search performed server-side. [isActive]
  /// filters by active flag; `null` means "both".
  Future<ProductsPageResult> listProductsPaged({
    required String companyId,
    required int offset,
    required int limit,
    String? categoryId,
    bool? isActive,
    String? searchQuery,
    ProductSortField sortField = ProductSortField.name,
    bool sortAscending = true,
  });

  /// Returns global counts of products for [companyId].
  ///
  /// Used by the KPI header so the numbers reflect the whole company and
  /// not just the current filter. Does not take a category or status
  /// filter.
  Future<ProductCounts> countProducts(String companyId);

  // ---------------------------------------------------------------------------
  // Products — mutations
  // ---------------------------------------------------------------------------

  Future<Product> createProduct({
    required String companyId,
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
  });

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
  });

  Future<void> deleteProduct(String productId);

  // ---------------------------------------------------------------------------
  // Product units
  // ---------------------------------------------------------------------------

  Future<List<ProductUnit>> listProductUnits(String productId);

  Future<ProductUnit> addProductUnit({
    required String productId,
    required String unitId,
    required double conversionFactor,
  });

  Future<ProductUnit> updateProductUnit({
    required String productUnitId,
    required double conversionFactor,
  });

  Future<void> deleteProductUnit(String productUnitId);
}
