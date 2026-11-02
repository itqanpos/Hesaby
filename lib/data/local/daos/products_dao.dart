// lib/data/local/daos/products_dao.dart

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/products_table.dart';
import '../tables/outbox_table.dart';

// ✅ استيراد الكيان الأصلي
import '../../../features/products/domain/entities/product.dart';

part 'products_dao.g.dart';

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

  Future<Product?> getProductById(String productId) async {
    final ProductRow? row = await (select(productsTable)
          ..where((t) => t.id.equals(productId)))
        .getSingleOrNull();
    return row?.toEntity();
  }

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
  // Write Operations
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
      await (delete(productsTable)..where((t) => t.id.equals(productId))).go();
      await _enqueueOutbox(
        companyId: companyId,
        operation: 'delete',
        recordId: productId,
        payload: '{"id": "$productId"}',
      );
    });
  }

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
        targetTable: 'products',
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

// ✅ إضافة Extension لتحويل ProductRow (Drift) إلى Product (Domain)
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
