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

/// الحالات المحتملة لعملية المزامنة.
enum SyncStatus {
  /// متصل، ولا توجد عمليات معلقة.
  idle,

  /// جاري إرسال العمليات إلى Supabase.
  syncing,

  /// لا يوجد اتصال بالإنترنت (أو Supabase غير متاح).
  offline,

  /// حدث خطأ أثناء المزامنة.
  error,
}

/// خدمة المزامنة (Sync Service).
///
/// المسؤولة عن:
/// 1. الاستماع لتغيرات الاتصال.
/// 2. قراءة جدول الـ Outbox بترتيب FIFO.
/// 3. إرسال البيانات إلى Supabase.
/// 4. حذف السجل من الـ Outbox عند النجاح.
class SyncService {
  SyncService(this._db, this._supabase) {
    _init();
  }

  final AppDatabase _db;
  final SupabaseClient _supabase;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isProcessing = false;

  /// بث (Stream) لحالة المزامنة لكي تعرضها الواجهة (مثلاً أيقونة التحميل).
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

  // ---------------------------------------------------------------------------
  // Initialization & Listening
  // ---------------------------------------------------------------------------

  void _init() {
    // الاستماع لتغيرات الشبكة
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (!results.contains(ConnectivityResult.none)) {
          // عاد الاتصال، لنبدأ المزامنة
          processOutbox();
        } else {
          _updateStatus(SyncStatus.offline);
        }
      },
    );

    // فحص أولي عند بدء التطبيق
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    final List<ConnectivityResult> results =
        await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      _updateStatus(SyncStatus.offline);
    } else {
      processOutbox();
    }
  }

  // ---------------------------------------------------------------------------
  // Core Processing Logic
  // ---------------------------------------------------------------------------

  /// الدالة الرئيسية التي تقرأ من الـ Outbox وترسل إلى Supabase.
  Future<void> processOutbox() async {
    if (_isProcessing) return; // منع التداخل

    _isProcessing = true;

    try {
      // 1. جلب العمليات المعلقة (FIFO)
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

      // 2. معالجة كل عنصر
      for (final OutboxRow item in pendingItems) {
        final bool success = await _processSingleItem(item);
        if (!success) {
          // إذا فشلنا بسبب الشبكة، نتوقف عن المعالجة فوراً
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

  /// معالجة عملية واحدة.
  /// ترجع `true` إذا نجحت، و `false` إذا فشلت بسبب الشبكة (لإيقاف الطابور).
  Future<bool> _processSingleItem(OutboxRow item) async {
    try {
      // تحديث الحالة إلى "جاري المزامنة"
      await (_db.update(_db.outboxTable)..where((t) => t.id.equals(item.id)))
          .write(const OutboxTableCompanion(status: Value('syncing')));

      final Map<String, dynamic> payload =
          jsonDecode(item.payload) as Map<String, dynamic>;

      if (item.operation == 'insert' || item.operation == 'update') {
        // Upsert يتعامل مع الإضافة والتحديث معاً (Idempotency)
        await _supabase.from(item.targetTable).upsert(payload);
      } else if (item.operation == 'delete') {
        // الحذف
        final String recordId = payload['id'] as String;
        await _supabase.from(item.targetTable).delete().eq('id', recordId);
      }

      // 3. النجاح! حذف السجل من الـ Outbox
      await (_db.delete(_db.outboxTable)..where((t) => t.id.equals(item.id))).go();
      
      return true;
    } on PostgrestException catch (error) {
      // خطأ من Supabase (مثلاً: قيد فريد مكسور، أو صلاحيات)
      // هذا خطأ دائم، لا فائدة من إعادة المحاولة، نسجله ونكمل.
      AppLogger.error('SyncService: Postgrest error on ${item.id}', error, StackTrace.current);
      
      await _markAsFailed(item, error.message);
      return true; // نكمل العنصر التالي
    } on Object catch (error, stackTrace) {
      // خطأ في الشبكة أو خطأ غير معروف
      // نعيد الحالة إلى "pending" لكي نعيد المحاولة لاحقاً
      AppLogger.warning('SyncService: Network error on ${item.id}, will retry later.');
      
      await (_db.update(_db.outboxTable)..where((t) => t.id.equals(item.id)))
          .write(const OutboxTableCompanion(status: Value('pending')));

      _updateStatus(SyncStatus.offline);
      return false; // نوقف المعالجة
    }
  }

  /// تسجيل فشل العملية بشكل دائم.
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

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  void dispose() {
    _connectivitySub?.cancel();
    _statusController.close();
  }
}

// ============================================================================
// Riverpod Providers
// ============================================================================

/// مزود (Provider) لخدمة المزامنة.
final Provider<SyncService> syncServiceProvider = Provider<SyncService>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final SupabaseClient supabase = Supabase.instance.client;

  final SyncService service = SyncService(db, supabase);

  // إغلاق الخدمة عند التخلص منها
  ref.onDispose(() => service.dispose());

  // بدء المزامنة تلقائياً عند بناء الـ Provider
  // (يتم استدعاؤه غالباً في main.dart أو AppShell)
  service.processOutbox();

  return service;
});

/// مزود لحالة المزامنة (لعرض شريط أو أيقونة في الواجهة).
final StreamProvider<SyncStatus> syncStatusProvider =
    StreamProvider<SyncStatus>((ref) {
  final SyncService service = ref.watch(syncServiceProvider);
  return service.statusStream;
});
