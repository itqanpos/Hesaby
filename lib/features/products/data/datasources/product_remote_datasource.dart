// lib/features/products/data/datasources/product_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/product_repository.dart';
import '../models/product_model.dart';
import '../models/product_unit_model.dart';

/// Thin wrapper around the Supabase queries for `products` and
/// `product_units`.
///
/// This is the only file within the products feature that talks to Supabase
/// directly for products and their unit conversions. Everything above this
/// class deals with [ProductModel] / [ProductUnitModel] and never sees
/// Supabase types.
///
/// Tenant isolation is enforced by Row Level Security and by composite
/// foreign keys:
/// * `products` rows are visible / writable only for companies where the
///   current user has an active membership (RLS).
/// * `products.category_id` / `products.default_unit_id` can only reference
///   a category / unit of the same company (composite FKs).
/// * `product_units` rows are similarly scoped by RLS and by composite FKs
///   on both the product and the unit.
///
/// The data source never accepts a `userId` and never trusts a
/// client-supplied identity. The active identity is always `auth.uid()`,
/// evaluated inside the database.
class ProductRemoteDataSource {
  const ProductRemoteDataSource(this._client);

  /// Active Supabase client, or `null` when Supabase was not initialised.
  final SupabaseClient? _client;

  /// Whether this data source can perform remote queries.
  bool get isAvailable => _client != null;

  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------

  /// Returns products of [companyId] visible to the current user.
  ///
  /// Inactive products are omitted unless [includeInactive] is `true`. When
  /// [categoryId] is provided, only products of that category are returned.
  /// Results are ordered by name.
  Future<List<ProductModel>> listProducts(
    String companyId, {
    required bool includeInactive,
    String? categoryId,
  }) async {
    final SupabaseClient client = _requireClient();

    // `var` infers `PostgrestFilterBuilder<PostgrestList>`. Reassignment is
    // used because filters must be applied conditionally; Dart preserves the
    // concrete type across reassignments of the same builder.
    var query = client.from('products').select().eq('company_id', companyId);

    if (!includeInactive) {
      query = query.eq('is_active', true);
    }
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }

    final List<Map<String, dynamic>> rows =
        await query.order('name', ascending: true);

    return rows.map(ProductModel.fromMap).toList(growable: false);
  }

  /// Returns the product with [productId], or throws if inaccessible.
  Future<ProductModel> getProduct(String productId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('products')
        .select()
        .eq('id', productId)
        .single();

    return ProductModel.fromMap(row);
  }

  /// Inserts a new product and returns the created row.
  Future<ProductModel> createProduct({
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
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': companyId,
      'name': name.trim(),
      'default_unit_id': defaultUnitId,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      if (categoryId != null) 'category_id': categoryId,
      if (sku != null && sku.trim().isNotEmpty) 'sku': sku.trim(),
      if (barcode != null && barcode.trim().isNotEmpty)
        'barcode': barcode.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (minSellingPrice != null) 'min_selling_price': minSellingPrice,
      if (taxRate != null) 'tax_rate': taxRate,
    };

    final Map<String, dynamic> row = await client
        .from('products')
        .insert(payload)
        .select()
        .single();

    return ProductModel.fromMap(row);
  }

  /// Updates an existing product and returns the updated row.
  ///
  /// Only non-null fields are sent, except for the six nullable columns that
  /// carry an explicit `clear*` flag to disambiguate "leave as is" from
  /// "set to null".
  Future<ProductModel> updateProduct({
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
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (defaultUnitId != null) 'default_unit_id': defaultUnitId,
      if (clearCategory) 'category_id': null,
      if (!clearCategory && categoryId != null) 'category_id': categoryId,
      if (clearSku) 'sku': null,
      if (!clearSku && sku != null) 'sku': sku.trim(),
      if (clearBarcode) 'barcode': null,
      if (!clearBarcode && barcode != null) 'barcode': barcode.trim(),
      if (clearDescription) 'description': null,
      if (!clearDescription && description != null)
        'description': description.trim(),
      if (costPrice != null) 'cost_price': costPrice,
      if (sellingPrice != null) 'selling_price': sellingPrice,
      if (clearMinSellingPrice) 'min_selling_price': null,
      if (!clearMinSellingPrice && minSellingPrice != null)
        'min_selling_price': minSellingPrice,
      if (clearTaxRate) 'tax_rate': null,
      if (!clearTaxRate && taxRate != null) 'tax_rate': taxRate,
      if (isActive != null) 'is_active': isActive,
    };

    final Map<String, dynamic> row = await client
        .from('products')
        .update(payload)
        .eq('id', productId)
        .select()
        .single();

    return ProductModel.fromMap(row);
  }

  /// Deletes the product with [productId].
  Future<void> deleteProduct(String productId) async {
    final SupabaseClient client = _requireClient();

    await client.from('products').delete().eq('id', productId);
  }

  // ---------------------------------------------------------------------------
  // Product units (non-base conversions)
  // ---------------------------------------------------------------------------

  /// Returns every non-base unit conversion of [productId], oldest first.
  Future<List<ProductUnitModel>> listProductUnits(String productId) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('product_units')
        .select()
        .eq('product_id', productId)
        .order('created_at', ascending: true);

    return rows.map(ProductUnitModel.fromMap).toList(growable: false);
  }

  /// Inserts a new non-base unit conversion for [productId].
  ///
  /// `company_id` is required by the database but is not part of the Domain
  /// interface. It is derived here by reading the product's `company_id`
  /// first. This keeps the repository interface free of a value that is
  /// always implied by the product, and it preserves tenant integrity: the
  /// subsequent composite FKs on `product_units` guarantee that the unit
  /// belongs to the same company as the product.
  Future<ProductUnitModel> addProductUnit({
    required String productId,
    required String unitId,
    required double conversionFactor,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> productRow = await client
        .from('products')
        .select('company_id')
        .eq('id', productId)
        .single();

    final Object? rawCompanyId = productRow['company_id'];
    if (rawCompanyId is! String || rawCompanyId.isEmpty) {
      throw const ProductException(
        type: ProductFailureType.invalidResponse,
        cause: 'Product row is missing a valid company_id.',
      );
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': rawCompanyId,
      'product_id': productId,
      'unit_id': unitId,
      'conversion_factor': conversionFactor,
    };

    final Map<String, dynamic> row = await client
        .from('product_units')
        .insert(payload)
        .select()
        .single();

    return ProductUnitModel.fromMap(row);
  }

  /// Updates the conversion factor of an existing product-unit row.
  Future<ProductUnitModel> updateProductUnit({
    required String productUnitId,
    required double conversionFactor,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('product_units')
        .update(<String, dynamic>{'conversion_factor': conversionFactor})
        .eq('id', productUnitId)
        .select()
        .single();

    return ProductUnitModel.fromMap(row);
  }

  /// Deletes a non-base unit conversion.
  Future<void> deleteProductUnit(String productUnitId) async {
    final SupabaseClient client = _requireClient();

    await client.from('product_units').delete().eq('id', productUnitId);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const ProductException(
        type: ProductFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    return client;
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
}
