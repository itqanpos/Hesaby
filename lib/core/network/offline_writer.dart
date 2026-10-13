// lib/core/network/offline_writer.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/companies/presentation/providers/company_context_provider.dart';
import '../utils/logger.dart';
import 'operation_queue.dart';
import 'operation_queue_providers.dart';
import 'pending_operation.dart';

/// Small helper for enqueueing write operations onto the offline queue.
///
/// **Design contract:**
///
/// Each helper takes the same input as the corresponding online write
/// path, generates a client UUID, builds a JSON-safe payload, and pushes
/// it onto the queue. The RPC functions on the server side use that UUID
/// for idempotency, so re-sending after a network timeout cannot create a
/// duplicate.
///
/// Callers are responsible for deciding **when** to queue (typically when
/// the device is offline or when a direct send failed with a network
/// error). These helpers never touch the network.
///
/// **Return value:** the generated client UUID, or `null` if the write
/// could not be queued (e.g. no company selected, queue not ready).
abstract final class OfflineWriter {
  static const Uuid _uuid = Uuid();

  /// Generates a fresh client UUID.
  static String newClientUuid() => _uuid.v4();

  // ---------------------------------------------------------------------------
  // Sale
  // ---------------------------------------------------------------------------

  /// Queues a sale.
  ///
  /// [items] must contain JSON-safe maps with the keys expected by the
  /// `create_offline_sale` RPC:
  ///
  /// ```dart
  /// {
  ///   'product_id': '<uuid>',
  ///   'unit_id':    '<uuid>',
  ///   'quantity':   2,
  ///   'unit_price': 100.0,
  ///   'notes':      null,
  /// }
  /// ```
  static Future<String?> enqueueSale({
    required WidgetRef ref,
    required String branchId,
    String? customerId,
    required DateTime saleDate,
    required List<Map<String, Object?>> items,
    double discount = 0,
    double taxAmount = 0,
    double paidAmount = 0,
    String? paymentMethod,
    String? notes,
    String? clientUuid,
  }) async {
    return _enqueue(
      ref: ref,
      type: PendingOperationType.sale,
      clientUuid: clientUuid,
      payload: <String, Object?>{
        'branch_id': branchId,
        'customer_id': customerId,
        'sale_date': saleDate.toUtc().toIso8601String(),
        'items': items,
        'discount': discount,
        'tax_amount': taxAmount,
        'paid_amount': paidAmount,
        'payment_method': paymentMethod,
        'notes': notes,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Customer payment
  // ---------------------------------------------------------------------------

  /// Queues a standalone customer payment.
  static Future<String?> enqueueCustomerPayment({
    required WidgetRef ref,
    required String customerId,
    required double amount,
    required String method,
    String? reference,
    String? notes,
    String? clientUuid,
  }) async {
    return _enqueue(
      ref: ref,
      type: PendingOperationType.customerPayment,
      clientUuid: clientUuid,
      payload: <String, Object?>{
        'customer_id': customerId,
        'amount': amount,
        'method': method,
        'reference': reference,
        'notes': notes,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Supplier payment
  // ---------------------------------------------------------------------------

  /// Queues a supplier payment.
  static Future<String?> enqueueSupplierPayment({
    required WidgetRef ref,
    required String supplierId,
    required double amount,
    required String method,
    String? reference,
    String? notes,
    String? clientUuid,
  }) async {
    return _enqueue(
      ref: ref,
      type: PendingOperationType.supplierPayment,
      clientUuid: clientUuid,
      payload: <String, Object?>{
        'supplier_id': supplierId,
        'amount': amount,
        'method': method,
        'reference': reference,
        'notes': notes,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Expense
  // ---------------------------------------------------------------------------

  /// Queues an expense.
  static Future<String?> enqueueExpense({
    required WidgetRef ref,
    required String branchId,
    required String categoryId,
    required double amount,
    required DateTime expenseDate,
    required String paymentMethod,
    String? notes,
    String? clientUuid,
  }) async {
    return _enqueue(
      ref: ref,
      type: PendingOperationType.expense,
      clientUuid: clientUuid,
      payload: <String, Object?>{
        'branch_id': branchId,
        'category_id': categoryId,
        'amount': amount,
        'expense_date': expenseDate.toUtc().toIso8601String(),
        'payment_method': paymentMethod,
        'notes': notes,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /// Shared enqueue logic. Resolves the current company, builds the
  /// [PendingOperation], and pushes it onto the queue.
  static Future<String?> _enqueue({
    required WidgetRef ref,
    required PendingOperationType type,
    required Map<String, Object?> payload,
    String? clientUuid,
  }) async {
    final String? companyId =
        ref.read(companyContextProvider).currentCompany?.id;
    if (companyId == null) {
      AppLogger.warning(
        'OfflineWriter: no company selected — cannot enqueue '
        '${type.name}.',
      );
      return null;
    }

    final OperationQueueRef queueRef = await _resolveQueue(ref);
    final OperationQueue? queue = queueRef.queue;
    if (queue == null) {
      AppLogger.warning(
        'OfflineWriter: queue not ready — cannot enqueue ${type.name}.',
      );
      return null;
    }

    final String uuid = clientUuid ?? newClientUuid();
    final PendingOperation operation = PendingOperation(
      clientUuid: uuid,
      type: type,
      companyId: companyId,
      payload: payload,
      createdAt: DateTime.now(),
    );

    try {
      await queue.enqueue(operation);
      AppLogger.info(
        'OfflineWriter: enqueued ${type.name} ($uuid).',
      );
      return uuid;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'OfflineWriter: failed to enqueue ${type.name}.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// Waits for the queue to be ready.
  ///
  /// The queue loads once at app start; if it is already available this
  /// returns synchronously without touching disk.
  static Future<OperationQueueRef> _resolveQueue(WidgetRef ref) async {
    try {
      final OperationQueue queue =
          await ref.read(operationQueueProvider.future);
      return OperationQueueRef(queue);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'OfflineWriter: failed to resolve the operation queue.',
        error,
        stackTrace,
      );
      return const OperationQueueRef(null);
    }
  }
}

/// Small wrapper around a possibly-null [OperationQueue] so that
/// [OfflineWriter._resolveQueue] can signal "queue not ready" without
/// throwing.
///
/// **Type-safe:** `queue` is `OperationQueue?`, not `dynamic` — so any
/// future rename or removal of a member on [OperationQueue] surfaces at
/// compile time.
class OperationQueueRef {
  const OperationQueueRef(this.queue);

  final OperationQueue? queue;
}
