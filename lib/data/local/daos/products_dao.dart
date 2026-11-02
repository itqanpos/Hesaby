// lib/data/local/daos/products_dao.dart

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/products_table.dart';
import '../tables/outbox_table.dart';

part 'products_dao.g.dart';

/// DAO (Data Access Object) for the `products` table.
///
/// This class is the ONLY way the application should read/write products
/// locally. It encapsulates the logic of writing to the `outbox` table
/// within the same transaction to guarantee Offline-First consistency.
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
    final SimpleSelectStatement<$ProductsTableTable, Product> query =
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

    return query.watch();
  }

  /// Gets a single product by its ID.
  Future<Product?> getProductById(String productId) {
    return (select(productsTable)
          ..where((t) => t.id.equals(productId)))
        .getSingleOrNull();
  }

  /// Gets a product by barcode (useful for POS scanning).
  Future<Product?> getProductByBarcode({
    required String companyId,
    required String barcode,
  }) {
    return (select(productsTable)
          ..where((t) =>
              t.companyId.equals(companyId) & t.barcode.equals(barcode)))
        .getSingleOrNull();
  }

  // ---------------------------------------------------------------------------
  // Write Operations (with Outbox)
  // ---------------------------------------------------------------------------

  /// Creates a new product locally and enqueues the operation in the outbox.
  ///
  /// [productPayload] is the JSON string (using the old `toMap()`) that will
  /// be sent to Supabase by the SyncService.
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
      // 1. Fetch the record before deleting to get its last known state (optional but good for audit)
      final Product? existing = await getProductById(productId);

      // 2. Delete from local products table
      await (delete(productsTable)..where((t) => t.id.equals(productId))).go();

      // 3. Insert into outbox
      if (existing != null) {
        await _enqueueOutbox(
          companyId: companyId,
          operation: 'delete',
          recordId: productId,
          payload: '{"id": "$productId"}', // Minimal payload for delete
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  /// Helper to insert a record into the outbox table.
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
        tableName: 'products',
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
