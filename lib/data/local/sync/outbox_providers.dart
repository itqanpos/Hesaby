// lib/data/local/sync/outbox_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_database.dart';
import 'sync_service.dart';

/// مزود لمراقبة عدد العمليات المعلقة في الـ Outbox لشركة معينة.
final pendingOutboxCountProvider =
    StreamProvider.family<int, String>((ref, companyId) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  return (db.select(db.outboxTable)
        ..where((t) => t.companyId.equals(companyId) & t.status.equals('pending')))
      .watch()
      .map((List<OutboxRow> rows) => rows.length);
});

/// مزود لمراقبة عدد العمليات الفاشلة في الـ Outbox لشركة معينة.
final failedOutboxCountProvider =
    StreamProvider.family<int, String>((ref, companyId) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  return (db.select(db.outboxTable)
        ..where((t) => t.companyId.equals(companyId) & t.status.equals('failed')))
      .watch()
      .map((List<OutboxRow> rows) => rows.length);
});
