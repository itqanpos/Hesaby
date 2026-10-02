// lib/features/products/presentation/providers/product_providers.dart

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

/// The application's product repository.
///
/// Builds a [ProductRepositoryImpl] from the active Supabase client. When
/// Supabase is not initialised (for example when credentials were not
/// provided at build time), the underlying data source wraps a `null`
/// client and every operation fails predictably with a
/// [ProductFailureType.unknown] exception instead of throwing a low-level
/// state error.
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

/// Provides the list of products for the currently selected company.
///
/// The notifier reloads automatically whenever [companyContextProvider]
/// reports a different `currentCompany.id`. When no company is selected, it
/// resolves to an empty list.
///
/// Note on naming: [AsyncNotifier] already declares an `update` method with
/// a different signature. Business operations are therefore named
/// `createProduct`, `updateProduct` and `deleteProduct`.
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

  /// Creates a new product for the currently selected company.
  ///
  /// Throws [ProductException] when there is no current company, or when
  /// the underlying repository rejects the operation (SKU / barcode
  /// conflict, category / unit not accessible).
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

    final Product created = await ref
        .read(productRepositoryProvider)
        .createProduct(
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
    return created;
  }

  /// Updates an existing product.
  ///
  /// Passing `null` for a nullable parameter leaves it unchanged, except for
  /// the six nullable fields that carry an explicit `clear*` flag:
  /// `categoryId`, `sku`, `barcode`, `description`, `minSellingPrice` and
  /// `taxRate`.
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
    final Product updated = await ref
        .read(productRepositoryProvider)
        .updateProduct(
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
    return updated;
  }

  /// Deletes a product.
  ///
  /// Throws [ProductException] with type [ProductFailureType.inUse] when the
  /// product is still referenced in a way that prevents deletion. Prefer
  /// [updateProduct] with `isActive: false` for a soft disable.
  Future<void> deleteProduct(String productId) async {
    await ref.read(productRepositoryProvider).deleteProduct(productId);
    await _reload();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

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

/// Provides the current company's products.
final AsyncNotifierProvider<ProductsNotifier, List<Product>> productsProvider =
    AsyncNotifierProvider<ProductsNotifier, List<Product>>(ProductsNotifier.new);

/// Provides the non-base unit conversions of a single product.
///
/// This is a *family* provider: the argument is the product id. Each product
/// keeps its own cached list, so mutating the conversions of one product does
/// not disturb the conversions of another, and does not reload the main
/// products list.
class ProductUnitsNotifier
    extends FamilyAsyncNotifier<List<ProductUnit>, String> {
  @override
  Future<List<ProductUnit>> build(String productId) async {
    return ref.read(productRepositoryProvider).listProductUnits(productId);
  }

  /// Adds a non-base unit conversion to the product this notifier is bound to.
  ///
  /// Throws [ProductException] with type [ProductFailureType.unitNotFound]
  /// when the unit is unavailable, or with
  /// [ProductFailureType.invalidResponse] when the row is rejected by the
  /// database (duplicate unit / base-unit collision).
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

  /// Updates the conversion factor of an existing product-unit row.
  Future<ProductUnit> updateProductUnit({
    required String productUnitId,
    required double conversionFactor,
  }) async {
    final ProductUnit updated = await ref
        .read(productRepositoryProvider)
        .updateProductUnit(
          productUnitId: productUnitId,
          conversionFactor: conversionFactor,
        );

    await _reload();
    return updated;
  }

  /// Deletes a non-base unit conversion.
  Future<void> deleteProductUnit(String productUnitId) async {
    await ref.read(productRepositoryProvider).deleteProductUnit(productUnitId);
    await _reload();
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the unit conversions of a single product, keyed by product id.
///
/// The declared type is `AsyncNotifierProviderFamily` — the concrete class
/// returned by `AsyncNotifierProvider.family<...>(...)`. Using the factory
/// constructor invocation itself as a type annotation is invalid Dart.
final AsyncNotifierProviderFamily<ProductUnitsNotifier, List<ProductUnit>,
        String> productUnitsProvider =
    AsyncNotifierProvider.family<ProductUnitsNotifier, List<ProductUnit>,
        String>(ProductUnitsNotifier.new);
