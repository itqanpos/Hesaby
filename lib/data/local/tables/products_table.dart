// lib/data/local/tables/products_table.dart

import 'package:drift/drift.dart';

/// Drift table definition for `products`.
///
/// Mirrors the [Product] domain entity exactly.
///
/// Important Notes:
/// * Monetary values are stored as [RealColumn] (which maps to `double` in Dart).
/// * `@TableIndex` declarations create local indexes for fast lookups
///   (e.g., searching by name or barcode offline).
/// * Unique constraints are enforced locally (matching the Supabase constraints)
///   to prevent duplicate SKUs or Barcodes before syncing.
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

  /// Unique identifier (UUID) generated locally or fetched from Supabase.
  TextColumn get id => text()();

  /// Owning company.
  TextColumn get companyId => text()();

  /// Optional category reference.
  TextColumn get categoryId => text().nullable()();

  /// Default base unit reference.
  TextColumn get defaultUnitId => text()();

  /// Display name.
  TextColumn get name => text()();

  /// Optional unique SKU per company.
  TextColumn get sku => text().nullable()();

  /// Optional unique barcode per company.
  TextColumn get barcode => text().nullable()();

  /// Optional description.
  TextColumn get description => text().nullable()();

  /// Cost price.
  RealColumn get costPrice => real()();

  /// Default selling price.
  RealColumn get sellingPrice => real()();

  /// Minimum allowed selling price.
  RealColumn get minSellingPrice => real().nullable()();

  /// Maximum allowed selling price.
  RealColumn get maxSellingPrice => real().nullable()();

  /// Optional tax rate (0-100).
  RealColumn get taxRate => real().nullable()();

  /// Status flag.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// Last update timestamp.
  DateTimeColumn get updatedAt => dateTime()();
}
