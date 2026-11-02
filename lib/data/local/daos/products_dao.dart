// lib/data/local/daos/products_dao.dart

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/products_table.dart';
import '../tables/outbox_table.dart';

part 'products_dao.g.dart';

/// DAO (Data Access Object) for the `products` table.
@DriftAccessor(tables: [ProductsTable, OutboxTable])
class ProductsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductsDaoMixin {
  ProductsDao(super.db);

  final Uuid _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // Read Operations
  // ---------------------------------------------------------------------------

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

  Future<Product?> getProductById(String productId) {
    return (select(productsTable)
          ..where((t) => t.id.equals(productId)))
        .getSingleOrNull();
  }

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

  Future<void> createProduct({
    required ProductsTableCompanion product,
    required String productPayload,
  }) async {
    await transaction(() async {
      await into(productsTable).insert(product);
      await _enqueueOutbox(
        companyId: product.companyId.value,
        operation: 'insert',
        recordId: product.id.value,
        payload: productPayload,
      );
    });
  }

  Future<void> updateProduct({
    required ProductsTableCompanion product,
    required String productPayload,
  }) async {
    await transaction(() async {
      await (update(productsTable)..where((t) => t.id.equals(product.id.value)))
          .write(product);
      await _enqueueOutbox(
        companyId: product.companyId.value,
        operation: 'update',
        recordId: product.id.value,
        payload: productPayload,
      );
    });
  }

  Future<void> deleteProduct({
    required String productId,
    required String companyId,
  }) async {
    await transaction(() async {
      final Product? existing = await getProductById(productId);
      await (delete(productsTable)..where((t) => t.id.equals(productId))).go();

      if (existing != null) {
        await _enqueueOutbox(
          companyId: companyId,
          operation: 'delete',
          recordId: productId,
          payload: '{"id": "$productId"}',
        );
      }
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
        targetTable: 'products', // ✅ تم التعديل هنا
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
