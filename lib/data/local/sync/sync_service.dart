// lib/data/local/sync/sync_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/logger.dart';
import '../app_database.dart';
import '../tables/outbox_table.dart';

enum SyncStatus {
  idle,
  syncing,
  offline,
  error,
}

class SyncService {
  SyncService(this._db, this._supabase) {
    _init();
  }

  final AppDatabase _db;
  final SupabaseClient _supabase;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isProcessing = false;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus _currentStatus = SyncStatus.idle;
  SyncStatus get currentStatus => _currentStatus;

  void _updateStatus(SyncStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _init() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (!results.contains(ConnectivityResult.none)) {
          unawaited(processOutbox()); // ✅ إصلاح تحذير الـ await
        } else {
          _updateStatus(SyncStatus.offline);
        }
      },
    );

    unawaited(_checkInitialConnection());
  }

  Future<void> _checkInitialConnection() async {
    final List<ConnectivityResult> results =
        await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      _updateStatus(SyncStatus.offline);
    } else {
      unawaited(processOutbox());
    }
  }

  Future<void> processOutbox() async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      final List<OutboxRow> pendingItems = await (_db.select(_db.outboxTable)
            ..where((t) => t.status.equals('pending'))
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt),
              (t) => OrderingTerm(expression: t.id),
            ]))
          .get();

      if (pendingItems.isEmpty) {
        _updateStatus(SyncStatus.idle);
        _isProcessing = false;
        return;
      }

      _updateStatus(SyncStatus.syncing);

      for (final OutboxRow item in pendingItems) {
        final bool success = await _processSingleItem(item);
        if (!success) {
          _isProcessing = false;
          return;
        }
      }

      _updateStatus(SyncStatus.idle);
    } on Object catch (error, stackTrace) {
      AppLogger.error('SyncService: Unexpected error', error, stackTrace);
      _updateStatus(SyncStatus.error);
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> _processSingleItem(OutboxRow item) async {
    try {
      await (_db.update(_db.outboxTable)..where((t) => t.id.equals(item.id)))
          .write(const OutboxTableCompanion(status: Value('syncing')));

      final Map<String, dynamic> payload =
          jsonDecode(item.payload) as Map<String, dynamic>;

      if (item.operation == 'insert' || item.operation == 'update') {
        await _supabase.from(item.targetTable).upsert(payload);
      } else if (item.operation == 'delete') {
        final String recordId = payload['id'] as String;
        await _supabase.from(item.targetTable).delete().eq('id', recordId);
      }

      await (_db.delete(_db.outboxTable)..where((t) => t.id.equals(item.id))).go();
      
      return true;
    } on PostgrestException catch (error) {
      AppLogger.error('SyncService: Postgrest error on ${item.id}', error, StackTrace.current);
      await _markAsFailed(item, error.message);
      return true; 
    } on Object catch (error) { // ✅ حذف stackTrace غير المستخدم
      AppLogger.warning('SyncService: Network error on ${item.id}, will retry later.');
      
      await (_db.update(_db.outboxTable)..where((t) => t.id.equals(item.id)))
          .write(const OutboxTableCompanion(status: Value('pending')));

      _updateStatus(SyncStatus.offline);
      return false; 
    }
  }

  Future<void> _markAsFailed(OutboxRow item, String error) async {
    await (_db.update(_db.outboxTable)..where((t) => t.id.equals(item.id)))
        .write(
      OutboxTableCompanion(
        status: const Value('failed'),
        retryCount: Value(item.retryCount + 1),
        lastError: Value(error),
      ),
    );
  }

  void dispose() {
    _connectivitySub?.cancel();
    _statusController.close();
  }
}

final Provider<SyncService> syncServiceProvider = Provider<SyncService>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final SupabaseClient supabase = Supabase.instance.client;

  final SyncService service = SyncService(db, supabase);

  ref.onDispose(() => service.dispose());

  return service;
});

final StreamProvider<SyncStatus> syncStatusProvider =
    StreamProvider<SyncStatus>((ref) {
  final SyncService service = ref.watch(syncServiceProvider);
  return service.statusStream;
});
