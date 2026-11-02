// lib/data/local/tables/customers_table.dart

import 'package:drift/drift.dart';

/// Drift table definition for `customers`.
///
/// Mirrors the [Customer] domain entity from `sale_entities.dart`.
///
/// Important Notes:
/// * Includes the `balance` column, which will be updated locally whenever
///   a sale or payment is made (so the UI can display it instantly offline).
/// * Unique constraints are added locally for `(companyId, code)` and
///   `(companyId, phone)` to prevent duplicates while offline.
/// * Indexes are added for fast local search by name/phone.
@TableIndex(name: 'idx_customers_company_id', columns: {#companyId})
@TableIndex(name: 'idx_customers_company_name', columns: {#companyId, #name})
@TableIndex(name: 'idx_customers_phone', columns: {#phone})
@TableIndex(name: 'uniq_customers_company_code', columns: {#companyId, #code}, unique: true)
@TableIndex(name: 'uniq_customers_company_phone', columns: {#companyId, #phone}, unique: true)
class CustomersTable extends Table {
  @override
  String get tableName => 'customers';

  @override
  Set<Column> get primaryKey => {id};

  /// Unique identifier (UUID).
  TextColumn get id => text()();

  /// Owning company.
  TextColumn get companyId => text()();

  /// Customer name.
  TextColumn get name => text()();

  /// Optional unique code per company.
  TextColumn get code => text().nullable()();

  /// Optional phone number.
  TextColumn get phone => text().nullable()();

  /// Optional email.
  TextColumn get email => text().nullable()();

  /// Optional address.
  TextColumn get address => text().nullable()();

  /// Optional notes.
  TextColumn get notes => text().nullable()();

  /// Current balance. 
  /// Positive = customer owes us (Debtor). 
  /// Negative = customer has credit (Creditor).
  RealColumn get balance => real().withDefault(const Constant(0.0))();

  /// Status flag.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// Last update timestamp.
  DateTimeColumn get updatedAt => dateTime()();
}
