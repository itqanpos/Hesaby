// lib/features/products/data/repositories/product_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_unit.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_remote_datasource.dart';
import '../models/product_model.dart';
import '../models/product_unit_model.dart';

/// Concrete implementation of [ProductRepository] backed by Supabase.
///
/// Responsibilities:
/// * Call the remote data source.
/// * Translate [ProductModel] / [ProductUnitModel] rows into pure
///   [Product] / [ProductUnit] entities.
/// * Translate Supabase / PostgREST errors into safe [ProductException]s
///   carrying a [ProductFailureType]. Raw backend messages never leave this
///   layer, and no credential or token is ever logged.
///
/// Typed error disambiguation:
/// Both partial unique indexes on `products` (`sku`, `barcode`) and both
/// composite foreign keys that guard cross-tenant references report generic
/// PostgreSQL codes (`23505`, `23503`). The specific failure type is
/// therefore resolved by inspecting the constraint name present in the
/// error text. Constraint names are declared in the Phase 4 migrations and
/// are stable, so this mapping is deterministic.
class ProductRepositoryImpl implements ProductRepository {
  const ProductRepositoryImpl(this._remoteDataSource);

  final ProductRemoteDataSource _remoteDataSource;

  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------

  @override
  Future<List<Product>> listProducts(
    String companyId, {
    bool includeInactive = false,
    String? categoryId,
  }) async {
    try {
      final List<ProductModel> models = await _remoteDataSource.listProducts(
        companyId,
        includeInactive: includeInactive,
        categoryId: categoryId,
      );
      return models
          .map((ProductModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'listProducts');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listProducts');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listProducts');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listProducts');
    }
  }

  @override
  Future<Product> getProduct(String productId) async {
    try {
      final ProductModel model =
          await _remoteDataSource.getProduct(productId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'getProduct');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getProduct');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getProduct');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getProduct');
    }
  }

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
  }) async {
    try {
      final ProductModel model = await _remoteDataSource.createProduct(
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
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'createProduct');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'createProduct');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'createProduct');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'createProduct');
    }
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
  }) async {
    try {
      final ProductModel model = await _remoteDataSource.updateProduct(
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
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'updateProduct');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateProduct');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateProduct');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateProduct');
    }
  }

  @override
  Future<void> deleteProduct(String productId) async {
    try {
      await _remoteDataSource.deleteProduct(productId);
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'deleteProduct');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'deleteProduct');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'deleteProduct');
    }
  }

  // ---------------------------------------------------------------------------
  // Product units (non-base conversions)
  // ---------------------------------------------------------------------------

  @override
  Future<List<ProductUnit>> listProductUnits(String productId) async {
    try {
      final List<ProductUnitModel> models =
          await _remoteDataSource.listProductUnits(productId);
      return models
          .map((ProductUnitModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'listProductUnits',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listProductUnits');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listProductUnits');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listProductUnits');
    }
  }

  @override
  Future<ProductUnit> addProductUnit({
    required String productId,
    required String unitId,
    required double conversionFactor,
  }) async {
    try {
      final ProductUnitModel model = await _remoteDataSource.addProductUnit(
        productId: productId,
        unitId: unitId,
        conversionFactor: conversionFactor,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'addProductUnit');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'addProductUnit');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'addProductUnit');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'addProductUnit');
    }
  }

  @override
  Future<ProductUnit> updateProductUnit({
    required String productUnitId,
    required double conversionFactor,
  }) async {
    try {
      final ProductUnitModel model =
          await _remoteDataSource.updateProductUnit(
        productUnitId: productUnitId,
        conversionFactor: conversionFactor,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'updateProductUnit',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateProductUnit');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateProductUnit');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateProductUnit');
    }
  }

  @override
  Future<void> deleteProductUnit(String productUnitId) async {
    try {
      await _remoteDataSource.deleteProductUnit(productUnitId);
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'deleteProductUnit');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'deleteProductUnit');
    } on ProductException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'deleteProductUnit');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static ProductException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" (FormatException).',
      error,
      stackTrace,
    );
    return ProductException(
      type: ProductFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static ProductException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final ProductFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'PostgREST error during "$operation" mapped to ${type.name} '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return ProductException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static ProductException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.warning(
      'Auth error during "$operation" mapped to unauthorized '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return ProductException(
      type: ProductFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static ProductException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final ProductFailureType type = _looksLikeNetworkFailure(error)
        ? ProductFailureType.network
        : ProductFailureType.unknown;

    AppLogger.error(
      'Unhandled error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return ProductException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Classifies a PostgREST error into a safe [ProductFailureType].
  ///
  /// Constraint names referenced below are declared in the Phase 4
  /// migrations:
  /// * `uniq_products_company_sku`      → skuConflict
  /// * `uniq_products_company_barcode`  → barcodeConflict
  /// * `products_category_company_fk`   → categoryNotFound
  /// * `products_default_unit_company_fk` → unitNotFound
  /// * `product_units_unit_company_fk`  → unitNotFound
  /// * `product_units_product_company_fk` → notFound (product row gone)
  /// * `product_units_product_unit_unique` → invalidResponse (duplicate
  ///   conversion, not a first-class Domain failure for Phase 4)
  static ProductFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    final String message = error.message.toLowerCase();
    final String full = error.toString().toLowerCase();

    if (code == '23505') {
      if (full.contains('uniq_products_company_sku')) {
        return ProductFailureType.skuConflict;
      }
      if (full.contains('uniq_products_company_barcode')) {
        return ProductFailureType.barcodeConflict;
      }
      if (full.contains('product_units_product_unit_unique')) {
        return ProductFailureType.invalidResponse;
      }
      return ProductFailureType.skuConflict;
    }

    if (code == '23503') {
      if (full.contains('products_category_company_fk')) {
        return ProductFailureType.categoryNotFound;
      }
      if (full.contains('products_default_unit_company_fk') ||
          full.contains('product_units_unit_company_fk')) {
        return ProductFailureType.unitNotFound;
      }
      if (full.contains('product_units_product_company_fk')) {
        return ProductFailureType.notFound;
      }
      return ProductFailureType.notFound;
    }

    if (code == 'PGRST116') {
      return ProductFailureType.notFound;
    }
    if (code.startsWith('42501') || code.startsWith('28')) {
      return ProductFailureType.unauthorized;
    }
    if (code.startsWith('42')) {
      return ProductFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return ProductFailureType.unauthorized;
    }

    // Textual fallbacks for environments where the constraint name is not
    // included in `error.code` (older PostgREST versions).
    if (full.contains('uniq_products_company_sku')) {
      return ProductFailureType.skuConflict;
    }
    if (full.contains('uniq_products_company_barcode')) {
      return ProductFailureType.barcodeConflict;
    }
    if (full.contains('products_category_company_fk')) {
      return ProductFailureType.categoryNotFound;
    }
    if (full.contains('products_default_unit_company_fk') ||
        full.contains('product_units_unit_company_fk')) {
      return ProductFailureType.unitNotFound;
    }
    if (full.contains('product_units_product_company_fk')) {
      return ProductFailureType.notFound;
    }

    if (message.contains('duplicate key') ||
        message.contains('unique constraint')) {
      return ProductFailureType.skuConflict;
    }

    if (message.contains('foreign key') ||
        message.contains('violates foreign key')) {
      return ProductFailureType.notFound;
    }

    if (_messageLooksLikeNetwork(message)) {
      return ProductFailureType.network;
    }

    return ProductFailureType.unknown;
  }

  static bool _looksLikeNetworkFailure(Object error) {
    final String description = error.toString().toLowerCase();
    return _messageLooksLikeNetwork(description);
  }

  static bool _messageLooksLikeNetwork(String value) {
    return value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection') ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('unreachable') ||
        value.contains('failed host lookup') ||
        value.contains('clientexception');
  }
}
