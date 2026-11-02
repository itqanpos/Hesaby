// lib/data/local/tables/customers_table.dart

import 'package:drift/drift.dart';

/// ✅ إضافة اسم مخصص للكلاس المولد لتجنب التعارض مع الكيان الأصلي
@DataClassName('CustomerRow')
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

  TextColumn get id => text()();
  TextColumn get companyId => text()();
  TextColumn get name => text()();
  TextColumn get code => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get balance => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}
