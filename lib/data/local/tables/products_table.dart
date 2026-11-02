// lib/data/local/tables/products_table.dart

import 'package:drift/drift.dart';

/// ✅ إضافة اسم مخصص للكلاس المولد لتجنب التعارض مع الكيان الأصلي
@DataClassName('ProductRow')
@TableIndex(name: 'idx_products_company_id', columns: {#companyId})
@TableIndex(name: 'idx_products_company_name', columns: {#companyId, #name})
@TableIndex(name: 'idx_products_barcode', columns: {#barcode})
@TableIndex(name: 'uniq_products_company_sku', columns: {#companyId, #sku}, unique: true)
@TableIndex(name: 'uniq_products_company_barcode', columns: {#companyId, #barcode}, unique: true)
class ProductsTable extends Table {
  @override
  String get tableName => 'products';

  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get companyId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get defaultUnitId => text()();
  TextColumn get name => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get description => text().nullable()();
  RealColumn get costPrice => real()();
  RealColumn get sellingPrice => real()();
  RealColumn get minSellingPrice => real().nullable()();
  RealColumn get maxSellingPrice => real().nullable()();
  RealColumn get taxRate => real().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}
