// lib/data/local/tables/outbox_table.dart

import 'package:drift/drift.dart';

/// Drift table definition for the `outbox`.
///
/// This is the heart of the Offline-First architecture.
/// Every write operation (Insert, Update, Delete) performed locally must
/// also insert a row here inside the same Transaction.
///
/// The [SyncService] reads this table in a FIFO manner (by `createdAt` and `id`),
/// sends the payload to Supabase, and deletes the row upon success.
@TableIndex(name: 'idx_outbox_status', columns: {#status})
@TableIndex(name: 'idx_outbox_created_at', columns: {#createdAt})
class OutboxTable extends Table {
  @override
  String get tableName => 'outbox';

  @override
  Set<Column> get primaryKey => {id};

  /// Unique operation ID (UUID).
  /// This also acts as the **Idempotency Key** when sending to Supabase
  /// (using upsert). If the app crashes mid-sync, resending won't duplicate data.
  TextColumn get id => text()();

  /// The company this operation belongs to.
  /// (Used to filter operations when switching companies).
  TextColumn get companyId => text()();

  /// The name of the target table in Supabase (e.g., 'products', 'customers').
  TextColumn get tableName => text()();

  /// The operation type: 'insert', 'update', 'delete'.
  TextColumn get operation => text()();

  /// The ID of the affected record (e.g., product ID).
  /// Useful for debugging and for applying specific logic during sync.
  TextColumn get recordId => text()();

  /// The JSON payload of the record to be sent to Supabase.
  /// (Stored as a String because Drift doesn't have a native JSON type).
  TextColumn get payload => text()();

  /// Current status: 'pending', 'syncing', 'failed'.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Number of sync attempts. Used for exponential backoff or max retries.
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// The last error message (if any), for debugging UI.
  TextColumn get lastError => text().nullable()();

  /// When this operation was created locally.
  /// Used to ensure FIFO (First-In-First-Out) processing.
  DateTimeColumn get createdAt => dateTime()();
}
