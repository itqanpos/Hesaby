// lib/data/local/app_database.dart

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// استيراد الجداول التي أنشأناها
import 'tables/products_table.dart';
import 'tables/customers_table.dart';
import 'tables/outbox_table.dart';

// سيتم توليد هذا الملف تلقائياً بواسطة build_runner
// (يجب أن يحتوي على تعليق part)
part 'app_database.g.dart';

/// قاعدة البيانات المحلية الرئيسية (Drift).
/// 
/// هذه القاعدة هي "مصدر الحقيقة الوحيد" (Single Source of Truth) 
/// في وضع الـ Offline. كل القراءات والكتابات تمر من هنا.
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
  /// نبدأ بـ 1. أي تغيير مستقبلي في الجداول يتطلب زيادة هذا الرقم
  /// وإضافة Migration Strategy.
  @override
  int get schemaVersion => 1;

  /// استراتيجية الترحيل (Migration Strategy).
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        // إنشاء كل الجداول عند أول تشغيل للتطبيق
        await m.createAll();
      },
      // يمكن إضافة onUpgrade هنا مستقبلاً عند إصدار schemaVersion 2
    );
  }
}

/// مزود (Provider) لـ Drift Database.
/// 
/// تم استخدام [driftDatabase] من حزمة `drift_flutter` لأنه يتولى
/// إعداد المنصات المختلفة تلقائياً:
/// * Android: يستخدم `sqlite3_flutter_libs`.
/// * Windows: يحمل `sqlite3.dll` تلقائياً.
/// * Web: يستخدم `WasmDatabase` (WASM) و `IndexedDB` كتخزين دائم.
/// * iOS: (مستبعد من المشروع).
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((Ref ref) {
  // إنشاء نسخة من قاعدة البيانات باستخدام الاسم المحدد
  final AppDatabase database = AppDatabase(
    driftDatabase(name: 'hesabi_local_db'),
  );

  // إغلاق قاعدة البيانات تلقائياً عند التخلص من الـ Provider
  ref.onDispose(() => database.close());

  return database;
});
