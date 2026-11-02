// lib/data/local/app_database.dart

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// استيراد الجداول
import 'tables/products_table.dart';
import 'tables/customers_table.dart';
import 'tables/outbox_table.dart';

// استيراد الـ DAOs
import 'daos/products_dao.dart';
import 'daos/customers_dao.dart';

part 'app_database.g.dart';

/// قاعدة البيانات المحلية الرئيسية (Drift).
@DriftDatabase(
  tables: [
    ProductsTable,
    CustomersTable,
    OutboxTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// إصدار المخطط (Schema Version).
  @override
  int get schemaVersion => 1;

  /// استراتيجية الترحيل (Migration Strategy).
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // DAOs (Data Access Objects) Getters
  // ---------------------------------------------------------------------------
  
  /// DAO الخاص بالمنتجات
  late final ProductsDao productsDao = ProductsDao(this);

  /// DAO الخاص بالعملاء
  late final CustomersDao customersDao = CustomersDao(this);
}

/// مزود (Provider) لـ Drift Database.
/// 
/// يستخدم [driftDatabase] من `drift_flutter` لإعداد المنصات تلقائياً
/// (Android, Windows, Web WASM).
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((Ref ref) {
  final AppDatabase database = AppDatabase(
    driftDatabase(name: 'hesabi_local_db'),
  );

  ref.onDispose(() => database.close());

  return database;
});
