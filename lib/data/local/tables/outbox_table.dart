// lib/data/local/tables/outbox_table.dart

import 'package:drift/drift.dart';

@DataClassName('OutboxRow') // ✅ تمت الإضافة
@TableIndex(name: 'idx_outbox_status', columns: {#status})
@TableIndex(name: 'idx_outbox_created_at', columns: {#createdAt})
class OutboxTable extends Table {
  @override
  String get tableName => 'outbox';

  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get companyId => text()();
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get operation => text()();
  TextColumn get recordId => text()();
  TextColumn get payload => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}
