// lib/data/local/daos/products_dao.dart

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/products_table.dart';
import '../tables/outbox_table.dart';

// ✅ استيراد الكيان الأصلي
import '../../../features/products/domain/entities/product.dart';

part 'products_dao.g.dart';

/// DAO (Data Access Object) for the `products` table.
///
/// Handles all local read/write operations for products.
@DriftAccessor(tables: [ProductsTable, OutboxTable])
class ProductsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductsDaoMixin {
  ProductsDao(super.db);

  final Uuid _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // Read Operations
  // ---------------------------------------------------------------------------

  /// Watches the list of products for a specific company.
  /// Used by Riverpod StreamProviders to auto-update the UI.
  Stream<List<Product>> watchProducts({
    required String companyId,
    bool includeInactive = false,
    String? categoryId,
    String? searchQuery,
    int? limit,
    int? offset,
  }) {
    final SimpleSelectStatement<$ProductsTableTable, ProductRow> query =
        select(productsTable)
          ..where((t) => t.companyId.equals(companyId));

    if (!includeInactive) {
      query.where((t) => t.isActive.equals(true));
    }

    if (categoryId != null && categoryId.isNotEmpty) {
      query.where((t) => t.categoryId.equals(categoryId));
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final String term = '%${searchQuery.trim()}%';
      query.where((t) =>
          t.name.like(term) |
          t.sku.like(term) |
          t.barcode.like(term));
    }

    query.orderBy([(t) => OrderingTerm(expression: t.name)]);

    if (limit != null) {
      query.limit(limit, offset: offset);
    }

    // ✅ تحويل النتيجة إلى كيان Product
    return query.watch().map((List<ProductRow> rows) =>
        rows.map((ProductRow row) => row.toEntity()).toList(growable: false));
  }

  /// Gets a single product by its ID.
  Future<Product?> getProductById(String productId) async {
    final ProductRow? row = await (select(productsTable)
          ..where((t) => t.id.equals(productId)))
        .getSingleOrNull();
    return row?.toEntity();
  }

  /// Gets a product by barcode (useful for POS scanning).
  Future<Product?> getProductByBarcode({
    required String companyId,
    required String barcode,
  }) async {
    final ProductRow? row = await (select(productsTable)
          ..where((t) =>
              t.companyId.equals(companyId) & t.barcode.equals(barcode)))
        .getSingleOrNull();
    return row?.toEntity();
  }

  // ---------------------------------------------------------------------------
  // Write Operations (with Outbox)
  // ---------------------------------------------------------------------------

  /// Creates a new product locally and enqueues the operation in the outbox.
  Future<void> createProduct({
    required ProductsTableCompanion product,
    required String productPayload,
  }) async {
    await transaction(() async {
      // 1. Insert into local products table
      await into(productsTable).insert(product);

      // 2. Insert into outbox
      await _enqueueOutbox(
        companyId: product.companyId.value,
        operation: 'insert',
        recordId: product.id.value,
        payload: productPayload,
      );
    });
  }

  /// Updates an existing product locally and enqueues the operation.
  Future<void> updateProduct({
    required ProductsTableCompanion product,
    required String productPayload,
  }) async {
    await transaction(() async {
      // 1. Update local products table
      await (update(productsTable)..where((t) => t.id.equals(product.id.value)))
          .write(product);

      // 2. Insert into outbox
      await _enqueueOutbox(
        companyId: product.companyId.value,
        operation: 'update',
        recordId: product.id.value,
        payload: productPayload,
      );
    });
  }

  /// Deletes a product locally and enqueues the delete operation.
  Future<void> deleteProduct({
    required String productId,
    required String companyId,
  }) async {
    await transaction(() async {
      // 1. Delete from local products table
      await (delete(productsTable)..where((t) => t.id.equals(productId))).go();

      // 2. Insert into outbox
      await _enqueueOutbox(
        companyId: companyId,
        operation: 'delete',
        recordId: productId,
        payload: '{"id": "$productId"}',
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  Future<void> _enqueueOutbox({
    required String companyId,
    required String operation,
    required String recordId,
    required String payload,
  }) async {
    await into(outboxTable).insert(
      OutboxTableCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        targetTable: 'products', // ✅ اسم الجدول في Supabase
        operation: operation,
        recordId: recordId,
        payload: payload,
        status: const Value('pending'),
        retryCount: const Value(0),
        createdAt: DateTime.now(),
      ),
    );
  }
}

// ============================================================================
// Extensions for Mapping
// ============================================================================

extension ProductRowMapper on ProductRow {
  Product toEntity() {
    return Product(
      id: id,
      companyId: companyId,
      defaultUnitId: defaultUnitId,
      name: name,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      categoryId: categoryId,
      sku: sku,
      barcode: barcode,
      description: description,
      minSellingPrice: minSellingPrice,
      maxSellingPrice: maxSellingPrice,
      taxRate: taxRate,
    );
  }
}

extension ProductDomainMapper on Product {
  /// يحول الكيان إلى Companion لاستخدامه في Drift
  ProductsTableCompanion toCompanion() {
    return ProductsTableCompanion(
      id: Value(id),
      companyId: Value(companyId),
      defaultUnitId: Value(defaultUnitId),
      name: Value(name),
      costPrice: Value(costPrice),
      sellingPrice: Value(sellingPrice),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      categoryId: Value(categoryId),
      sku: Value(sku),
      barcode: Value(barcode),
      description: Value(description),
      minSellingPrice: Value(minSellingPrice),
      maxSellingPrice: Value(maxSellingPrice),
      taxRate: Value(taxRate),
    );
  }

  /// يحول الكيان إلى JSON لإرساله في الـ Outbox (متوافق مع Supabase snake_case)
  String toJsonPayload() {
    return jsonEncode({
      'id': id,
      'company_id': companyId,
      'default_unit_id': defaultUnitId,
      'name': name,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'category_id': categoryId,
      'sku': sku,
      'barcode': barcode,
      'description': description,
      'min_selling_price': minSellingPrice,
      'max_selling_price': maxSellingPrice,
      'tax_rate': taxRate,
    });
  }
}
