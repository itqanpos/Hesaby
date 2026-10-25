// lib/features/products/data/repositories/cached_product_repository.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/json_local_cache.dart';
import '../../../../core/cache/local_cache_provider.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_unit.dart';
import '../../domain/repositories/product_repository.dart';
import '../models/product_model.dart';
import '../models/product_unit_model.dart';

/// Offline-first decorator around [ProductRepository].
class CachedProductRepositoryImpl implements ProductRepository {
  CachedProductRepositoryImpl({
    required ProductRepository remote,
    required Ref ref,
  })  : _remote = remote,
        _ref = ref;

  final ProductRepository _remote;
  final Ref _ref;

  static const String _productsPrefix = 'products';
  static const String _unitsPrefix = 'product_units';

  Future<JsonLocalCache?> _cache() async {
    try {
      return await _ref.read(jsonLocalCacheProvider.future);
    } on Object {
      return null;
    }
  }

  static Map<String, Object?> _productToMap(Product p) {
    return <String, Object?>{
      'id': p.id,
      'company_id': p.companyId,
      'category_id': p.categoryId,
      'default_unit_id': p.defaultUnitId,
      'name': p.name,
      'sku': p.sku,
      'barcode': p.barcode,
      'description': p.description,
      'cost_price': p.costPrice,
      'selling_price': p.sellingPrice,
      'min_selling_price': p.minSellingPrice,
      'max_selling_price': p.maxSellingPrice,
      'tax_rate': p.taxRate,
      'is_active': p.isActive,
      'created_at': p.createdAt.toUtc().toIso8601String(),
      'updated_at': p.updatedAt.toUtc().toIso8601String(),
    };
  }

  static Map<String, Object?> _unitToMap(ProductUnit u) {
    return <String, Object?>{
      'id': u.id,
      'product_id': u.productId,
      'unit_id': u.unitId,
      'conversion_factor': u.conversionFactor,
      'selling_price': u.sellingPrice,
      'min_selling_price': u.minSellingPrice,
      'max_selling_price': u.maxSellingPrice,
    };
  }

  @override
  Future<List<Product>> listProducts(
    String companyId, {
    bool includeInactive = false,
    String? categoryId,
  }) async {
    try {
      final List<Product> fresh = await _remote.listProducts(
        companyId,
        includeInactive: includeInactive,
        categoryId: categoryId,
      );

      if (!includeInactive && categoryId == null) {
        final cache = await _cache();
        if (cache != null) {
          await cache.saveList(
            prefix: _productsPrefix,
            companyId: companyId,
            items: fresh.map(_productToMap).toList(growable: false),
          );
        }
      }

      return fresh;
    } on ProductException catch (error) {
      if (error.type == ProductFailureType.network) {
        final cache = await _cache();
        if (cache != null) {
          final List<Map<String, dynamic>>? cached = cache.loadList(
            prefix: _productsPrefix,
            companyId: companyId,
          );
          if (cached != null && cached.isNotEmpty) {
            AppLogger.info(
              'CachedProductRepository: serving ${cached.length} products from cache.',
            );
            return cached
                .map((m) => ProductModel.fromMap(m).toEntity())
                .toList(growable: false);
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<Product> getProduct(String productId) async {
    return _remote.getProduct(productId);
  }

  @override
  Future<ProductsPageResult> listProductsPaged({
    required String companyId,
    required int offset,
    required int limit,
    String? categoryId,
    bool? isActive,
    String? searchQuery,
    ProductSortField sortField = ProductSortField.name,
    bool sortAscending = true,
  }) async {
    try {
      final ProductsPageResult fresh = await _remote.listProductsPaged(
        companyId: companyId,
        offset: offset,
        limit: limit,
        categoryId: categoryId,
        isActive: isActive,
        searchQuery: searchQuery,
        sortField: sortField,
        sortAscending: sortAscending,
      );

      if (offset == 0 &&
          categoryId == null &&
          isActive == null &&
          (searchQuery == null || searchQuery.isEmpty)) {
        final cache = await _cache();
        if (cache != null) {
          await cache.saveList(
            prefix: _productsPrefix,
            companyId: companyId,
            items: fresh.items.map(_productToMap).toList(growable: false),
          );
        }
      }

      return fresh;
    } on ProductException catch (error) {
      if (error.type == ProductFailureType.network) {
        final cache = await _cache();
        if (cache != null) {
          final List<Map<String, dynamic>>? cached = cache.loadList(
            prefix: _productsPrefix,
            companyId: companyId,
          );
          if (cached != null && cached.isNotEmpty) {
            List<Product> all = cached
                .map((m) => ProductModel.fromMap(m).toEntity())
                .toList(growable: false);

            if (isActive != null) {
              all = all.where((p) => p.isActive == isActive).toList();
            }
            if (categoryId != null) {
              all = all.where((p) => p.categoryId == categoryId).toList();
            }
            if (searchQuery != null && searchQuery.trim().isNotEmpty) {
              final String q = searchQuery.toLowerCase().trim();
              all = all.where((p) {
                return p.name.toLowerCase().contains(q) ||
                    (p.sku?.toLowerCase().contains(q) ?? false) ||
                    (p.barcode?.toLowerCase().contains(q) ?? false);
              }).toList();
            }

            int compare(Product a, Product b) {
              int result;
              switch (sortField) {
                case ProductSortField.name:
                  result = a.name.compareTo(b.name);
                  break;
                case ProductSortField.sellingPrice:
                  result = a.sellingPrice.compareTo(b.sellingPrice);
                  break;
                case ProductSortField.costPrice:
                  result = a.costPrice.compareTo(b.costPrice);
                  break;
                case ProductSortField.createdAt:
                  result = a.createdAt.compareTo(b.createdAt);
                  break;
              }
              return sortAscending ? result : -result;
            }
            all.sort(compare);

            final int start = offset.clamp(0, all.length);
            final int end = (offset + limit).clamp(0, all.length);
            final List<Product> page = all.sublist(start, end);

            return ProductsPageResult(
              items: page,
              offset: offset,
              limit: limit,
              hasMore: end < all.length,
            );
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<ProductCounts> countProducts(String companyId) async {
    try {
      return await _remote.countProducts(companyId);
    } on ProductException catch (error) {
      if (error.type == ProductFailureType.network) {
        final cache = await _cache();
        if (cache != null) {
          final List<Map<String, dynamic>>? cached = cache.loadList(
            prefix: _productsPrefix,
            companyId: companyId,
          );
          if (cached != null) {
            final List<Product> all = cached
                .map((m) => ProductModel.fromMap(m).toEntity())
                .toList(growable: false);
            return ProductCounts(
              total: all.length,
              active: all.where((p) => p.isActive).length,
              inactive: all.where((p) => !p.isActive).length,
            );
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<List<ProductUnit>> listProductUnits(String productId) async {
    try {
      final List<ProductUnit> fresh =
          await _remote.listProductUnits(productId);

      final cache = await _cache();
      if (cache != null) {
        await cache.saveList(
          prefix: _unitsPrefix,
          companyId: productId,
          items: fresh.map(_unitToMap).toList(growable: false),
        );
      }

      return fresh;
    } on ProductException catch (error) {
      if (error.type == ProductFailureType.network) {
        final cache = await _cache();
        if (cache != null) {
          final List<Map<String, dynamic>>? cached = cache.loadList(
            prefix: _unitsPrefix,
            companyId: productId,
          );
          if (cached != null) {
            return cached
                .map((m) => ProductUnitModel.fromMap(m).toEntity())
                .toList(growable: false);
          }
        }
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations — delegate directly
  // ---------------------------------------------------------------------------

  @override
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
  }) {
    return _remote.createProduct(
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
  }

  @override
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
  }) {
    return _remote.updateProduct(
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
  }

  @override
  Future<void> deleteProduct(String productId) {
    return _remote.deleteProduct(productId);
  }

  @override
  Future<ProductUnit> addProductUnit({
    required String productId,
    required String unitId,
    required double conversionFactor,
  }) {
    return _remote.addProductUnit(
      productId: productId,
      unitId: unitId,
      conversionFactor: conversionFactor,
    );
  }

  @override
  Future<ProductUnit> updateProductUnit({
    required String productUnitId,
    required double conversionFactor,
  }) {
    return _remote.updateProductUnit(
      productUnitId: productUnitId,
      conversionFactor: conversionFactor,
    );
  }

  @override
  Future<void> deleteProductUnit(String productUnitId) {
    return _remote.deleteProductUnit(productUnitId);
  }

  // ---------------------------------------------------------------------------
  // Prefetch
  // ---------------------------------------------------------------------------

  Future<void> prefetchCatalog(String companyId) async {
    try {
      final List<Product> products = await _remote.listProducts(
        companyId,
        includeInactive: false,
      );

      final cache = await _cache();
      if (cache == null) return;

      await cache.saveList(
        prefix: _productsPrefix,
        companyId: companyId,
        items: products.map(_productToMap).toList(growable: false),
      );

      await Future.wait<void>(
        products.map((Product p) async {
          try {
            final List<ProductUnit> units =
                await _remote.listProductUnits(p.id);
            await cache.saveList(
              prefix: _unitsPrefix,
              companyId: p.id,
              items: units.map(_unitToMap).toList(growable: false),
            );
          } on Object {
            // Skip individual failures.
          }
        }),
      );

      AppLogger.info(
        'CachedProductRepository: prefetched ${products.length} products + units for $companyId.',
      );
    } on Object catch (error) {
      AppLogger.warning('Catalog prefetch failed: $error');
    }
  }
}
