// lib/features/products/domain/repositories/product_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/product.dart';
import '../entities/product_unit.dart';

/// Categories of failures that the presentation layer can safely translate
/// into localized user messages.
///
/// Mirrors the Phase 1 and Phase 3 conventions so the application has a
/// single, consistent way of categorising safe failures. Backend-specific
/// error codes and raw messages never leave the data layer.
enum ProductFailureType {
  /// The request could not reach the backend.
  network,

  /// The backend rejected the request as unauthorised (RLS or session).
  unauthorized,

  /// The requested product does not exist or is not accessible.
  notFound,

  /// A product with the same SKU already exists for this company.
  skuConflict,

  /// A product with the same barcode already exists for this company.
  barcodeConflict,

  /// The referenced category does not exist, is not accessible, or belongs
  /// to a different company.
  categoryNotFound,

  /// The referenced unit does not exist, is not accessible, or belongs to a
  /// different company.
  unitNotFound,

  /// The product cannot be deleted because other rows still reference it.
  inUse,

  /// The response could not be interpreted.
  invalidResponse,

  /// Any other unclassified failure.
  unknown,
}

/// Domain-level exception raised by [ProductRepository] operations.
///
/// Carries a safe [ProductFailureType] rather than a raw backend message so
/// the presentation layer can produce localized, user-friendly errors.
@immutable
class ProductException extends Equatable implements Exception {
  const ProductException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  /// Safe, categorized reason for the failure.
  final ProductFailureType type;

  /// Original error, kept for logging. Never displayed to end users.
  final Object? cause;

  /// Original stack trace, kept for logging.
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'ProductException(type: ${type.name})';
}

/// Contract for product operations, including their non-base unit
/// conversions.
///
/// All access decisions are ultimately enforced by Row Level Security in the
/// database: the data layer never accepts a `userId`, and `companyId` is
/// only ever used to filter results — RLS rejects any attempt to read or
/// write rows outside the caller's memberships.
abstract interface class ProductRepository {
  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------

  /// Returns every product of [companyId] visible to the current user.
  ///
  /// When [includeInactive] is `false` (the default), inactive products are
  /// omitted. When [categoryId] is provided, only products of that category
  /// are returned.
  /// Throws [ProductException] when the request fails.
  Future<List<Product>> listProducts(
    String companyId, {
    bool includeInactive = false,
    String? categoryId,
  });

  /// Returns a single product by id.
  ///
  /// Throws [ProductException] with type [ProductFailureType.notFound] when
  /// the product does not exist or is not accessible to the current user.
  Future<Product> getProduct(String productId);

  /// Creates a new product inside [companyId].
  ///
  /// [defaultUnitId] must reference a unit of the same company.
  /// [categoryId], when provided, must reference a category of the same
  /// company.
  ///
  /// Throws [ProductException] with type
  /// [ProductFailureType.skuConflict] / [ProductFailureType.barcodeConflict]
  /// on uniqueness violations, or [ProductFailureType.categoryNotFound] /
  /// [ProductFailureType.unitNotFound] when a referenced row is unavailable.
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

  /// Updates an existing product.
  ///
  /// Passing `null` for a nullable parameter leaves it unchanged, except for
  /// the six nullable fields that carry an explicit `clear*` flag:
  /// `categoryId`, `sku`, `barcode`, `description`, `minSellingPrice` and
  /// `taxRate`. This resolves the ambiguity of `null` meaning both "leave as
  /// is" and "set to null".
  ///
  /// Throws [ProductException] with the same typed failures as
  /// [createProduct].
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

  /// Deletes a product.
  ///
  /// Throws [ProductException] with type [ProductFailureType.inUse] when the
  /// product is still referenced by other rows in a way that prevents
  /// deletion. Callers should prefer [updateProduct] with `isActive: false`
  /// for a soft disable.
  Future<void> deleteProduct(String productId);

  // ---------------------------------------------------------------------------
  // Product units (non-base conversions)
  // ---------------------------------------------------------------------------

  /// Returns every non-base unit conversion of [productId].
  ///
  /// The base unit of the product (`Product.defaultUnitId`) is intentionally
  /// not included: it is a property of the product itself.
  /// Throws [ProductException] when the request fails.
  Future<List<ProductUnit>> listProductUnits(String productId);

  /// Adds a new non-base unit conversion to [productId].
  ///
  /// [conversionFactor] must be strictly positive. [unitId] must reference a
  /// unit of the same company, and must not equal the product's base unit.
  ///
  /// Throws [ProductException] with type [ProductFailureType.unitNotFound]
  /// when the unit is unavailable, or with [ProductFailureType.invalidResponse]
  /// when the DB rejects the row (duplicate unit or base-unit collision).
  Future<ProductUnit> addProductUnit({
    required String productId,
    required String unitId,
    required double conversionFactor,
  });

  /// Updates the conversion factor of an existing product-unit row.
  ///
  /// Throws [ProductException] when the row is not accessible or the factor
  /// is not strictly positive.
  Future<ProductUnit> updateProductUnit({
    required String productUnitId,
    required double conversionFactor,
  });

  /// Deletes a non-base unit conversion.
  ///
  /// Throws [ProductException] when the row is not accessible.
  Future<void> deleteProductUnit(String productUnitId);
}
