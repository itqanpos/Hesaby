// lib/core/network/operation_senders.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/logger.dart';
import 'pending_operation.dart';
import 'operation_processor.dart';

/// Concrete [PendingOperationSender] that dispatches each queued
/// operation to the appropriate Supabase endpoint.
///
/// **Design decision: direct RPC.**
///
/// Rather than routing through the repository layer (which was written for
/// the interactive, online-only flow), the sender talks to Supabase
/// directly via four purpose-built **idempotent RPC functions**:
///
/// | Operation type    | RPC function               |
/// |-------------------|----------------------------|
/// | sale              | `create_offline_sale`      |
/// | customerPayment   | `create_offline_customer_payment` |
/// | supplierPayment   | `create_offline_supplier_payment` |
/// | expense           | `create_offline_expense`   |
///
/// Each function receives the client-generated `client_uuid` and:
/// 1. Inserts the row with `client_uuid` set.
/// 2. If a row with the same `(company_id, client_uuid)` already exists,
///    returns success without re-inserting (idempotent).
/// 3. Runs the same triggers that the online flow uses.
///
/// This keeps the sender self-contained, avoids touching every repository
/// in the app, and guarantees that business logic (invoice numbering,
/// balances, cash triggers) runs uniformly whether the operation arrives
/// online or via the offline queue.
///
/// The matching SQL migrations are provided separately
/// (31, 32, 33).
class SupabaseOperationSender implements PendingOperationSender {
  SupabaseOperationSender({required SupabaseClient client})
      : _client = client;

  final SupabaseClient _client;

  /// Hard ceiling on a single RPC call.
  ///
  /// Prevents a stuck network call from blocking the queue indefinitely.
  /// When the limit is hit, a [TimeoutException] is thrown; the processor
  /// classifies it as **transient** and retries without consuming the
  /// retry budget.
  static const Duration _rpcTimeout = Duration(seconds: 20);

  @override
  Future<void> send(PendingOperation operation) async {
    switch (operation.type) {
      case PendingOperationType.sale:
        await _sendSale(operation);
      case PendingOperationType.customerPayment:
        await _sendCustomerPayment(operation);
      case PendingOperationType.supplierPayment:
        await _sendSupplierPayment(operation);
      case PendingOperationType.expense:
        await _sendExpense(operation);
    }
  }

  // ---------------------------------------------------------------------------
  // Sale
  // ---------------------------------------------------------------------------

  Future<void> _sendSale(PendingOperation op) async {
    // Expected payload (as produced by OfflineWriter.enqueueSale):
    // {
    //   "branch_id":      "<uuid>",
    //   "customer_id":    "<uuid>|null",
    //   "sale_date":      "2026-10-12T10:30:00.000Z",
    //   "items": [
    //     {"product_id": "<uuid>", "unit_id": "<uuid>",
    //      "quantity": 2, "unit_price": 100.0, "notes": null}
    //   ],
    //   "discount":       0.0,
    //   "tax_amount":     0.0,
    //   "paid_amount":    100.0,
    //   "payment_method": "cash",
    //   "notes":          null
    // }
    await _callRpc(
      name: 'create_offline_sale',
      body: <String, Object?>{
        'p_company_id': op.companyId,
        'p_client_uuid': op.clientUuid,
        'p_payload': op.payload,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Customer payment
  // ---------------------------------------------------------------------------

  Future<void> _sendCustomerPayment(PendingOperation op) async {
    // Expected payload:
    // {
    //   "customer_id": "<uuid>",
    //   "amount":      500.0,
    //   "method":      "cash" | "card" | "wallet" | "transfer",
    //   "reference":   null,
    //   "notes":       null
    // }
    await _callRpc(
      name: 'create_offline_customer_payment',
      body: <String, Object?>{
        'p_company_id': op.companyId,
        'p_client_uuid': op.clientUuid,
        'p_payload': op.payload,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Supplier payment
  // ---------------------------------------------------------------------------

  Future<void> _sendSupplierPayment(PendingOperation op) async {
    // Expected payload:
    // {
    //   "supplier_id": "<uuid>",
    //   "amount":      300.0,
    //   "method":      "cash" | "card" | "wallet" | "transfer",
    //   "reference":   null,
    //   "notes":       null
    // }
    await _callRpc(
      name: 'create_offline_supplier_payment',
      body: <String, Object?>{
        'p_company_id': op.companyId,
        'p_client_uuid': op.clientUuid,
        'p_payload': op.payload,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Expense
  // ---------------------------------------------------------------------------

  Future<void> _sendExpense(PendingOperation op) async {
    // Expected payload:
    // {
    //   "branch_id":      "<uuid>",
    //   "category_id":    "<uuid>",
    //   "amount":         150.0,
    //   "expense_date":   "2026-10-12T10:30:00.000Z",
    //   "payment_method": "cash" | "card" | "wallet" | "transfer",
    //   "notes":          null
    // }
    await _callRpc(
      name: 'create_offline_expense',
      body: <String, Object?>{
        'p_company_id': op.companyId,
        'p_client_uuid': op.clientUuid,
        'p_payload': op.payload,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // RPC helper
  // ---------------------------------------------------------------------------

  /// Calls [name] with [body] and translates the response into the success
  /// / failure contract expected by [PendingOperationSender.send].
  ///
  /// * Success → returns normally.
  /// * `23505` duplicate-key → treated as success (idempotency belt-and-
  ///   braces on top of the UNIQUE index and the SQL-level guard).
  /// * Any other exception, including [TimeoutException] — rethrown
  ///   unchanged so the processor can classify it (transient vs permanent)
  ///   and decide whether to retry.
  ///
  /// The call is bounded by [_rpcTimeout]; a stuck network cannot pin the
  /// processor forever.
  Future<void> _callRpc({
    required String name,
    required Map<String, Object?> body,
  }) async {
    try {
      await _client
          .rpc(name, params: body)
          .timeout(_rpcTimeout);
    } on PostgrestException catch (error) {
      // Duplicate client_uuid → someone else already delivered this
      // operation (e.g. a retry that we thought had failed). Treat as
      // success.
      if (error.code == '23505') {
        AppLogger.info(
          'OperationSender: $name reported duplicate client_uuid — '
          'treating as success.',
        );
        return;
      }
      rethrow;
    }
  }
}

// ============================================================================
// Factory / providers integration
// ============================================================================

/// Returns a [SupabaseOperationSender] bound to the current Supabase
/// client.
///
/// Throws [StateError] when `Supabase.instance` is not initialized — that
/// situation should never happen at runtime because the app initializes
/// Supabase in `bootstrap/app_initializer.dart`.
SupabaseOperationSender buildSupabaseOperationSender() {
  final SupabaseClient client;
  try {
    client = Supabase.instance.client;
  } on Object catch (error) {
    throw StateError(
      'Supabase is not initialized. Cannot build an operation sender. '
      'Underlying error: $error',
    );
  }
  return SupabaseOperationSender(client: client);
}
