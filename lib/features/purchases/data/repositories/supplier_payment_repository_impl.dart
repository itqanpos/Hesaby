// lib/features/purchases/data/repositories/supplier_payment_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/supplier_payment.dart';
import '../../domain/repositories/supplier_payment_repository.dart';
import '../models/supplier_payment_model.dart';

/// Concrete implementation of [SupplierPaymentRepository] backed by
/// Supabase.
///
/// Talks directly to the `supplier_payments` table. A separate datasource
/// layer is omitted on purpose: the surface is only four operations, and
/// the queries are simple enough that a datasource would add indirection
/// without value.
class SupplierPaymentRepositoryImpl implements SupplierPaymentRepository {
  const SupplierPaymentRepositoryImpl(this._client);

  final supabase.SupabaseClient? _client;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  @override
  Future<List<SupplierPayment>> listPaymentsForSupplier(
    String supplierId, {
    int? limit,
  }) async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      final int effectiveLimit = (limit == null || limit <= 0) ? 200 : limit;

      // RLS scopes rows to the caller's company. The chain is built in a
      // single expression because `.order()` / `.limit()` return a
      // different builder type from `.eq()`.
      final List<Map<String, dynamic>> rows = await client
          .from('supplier_payments')
          .select()
          .eq('supplier_id', supplierId)
          .order('payment_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(effectiveLimit);

      return rows
          .map(SupplierPaymentModel.fromMap)
          .map((SupplierPaymentModel m) => m.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'listPaymentsForSupplier',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'listPaymentsForSupplier',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'listPaymentsForSupplier',
      );
    } on SupplierPaymentException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'listPaymentsForSupplier',
      );
    }
  }

  @override
  Future<List<SupplierPayment>> listPaymentsForPurchase(
    String purchaseId,
  ) async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      final List<Map<String, dynamic>> rows = await client
          .from('supplier_payments')
          .select()
          .eq('purchase_id', purchaseId)
          .order('payment_date', ascending: false)
          .order('created_at', ascending: false);

      return rows
          .map(SupplierPaymentModel.fromMap)
          .map((SupplierPaymentModel m) => m.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(
        error,
        stackTrace,
        operation: 'listPaymentsForPurchase',
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'listPaymentsForPurchase',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'listPaymentsForPurchase',
      );
    } on SupplierPaymentException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'listPaymentsForPurchase',
      );
    }
  }

  @override
  Future<double> sumPaymentsForSupplier(String supplierId) async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      final List<Map<String, dynamic>> rows = await client
          .from('supplier_payments')
          .select('amount')
          .eq('supplier_id', supplierId);

      double total = 0;
      for (final Map<String, dynamic> row in rows) {
        final Object? raw = row['amount'];
        if (raw is num) {
          total += raw.toDouble();
        } else if (raw is String) {
          final double? parsed = double.tryParse(raw);
          if (parsed != null) total += parsed;
        }
      }
      return total;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(
        error,
        stackTrace,
        operation: 'sumPaymentsForSupplier',
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(
        error,
        stackTrace,
        operation: 'sumPaymentsForSupplier',
      );
    } on SupplierPaymentException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(
        error,
        stackTrace,
        operation: 'sumPaymentsForSupplier',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  @override
  Future<SupplierPayment> recordPayment({
    required String companyId,
    required String supplierId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    String? purchaseId,
    String? reference,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw const SupplierPaymentException(
        type: SupplierPaymentFailureType.invalidAmount,
      );
    }
    if (!SupplierPaymentMethod.all.contains(paymentMethod)) {
      throw const SupplierPaymentException(
        type: SupplierPaymentFailureType.invalidMethod,
      );
    }

    try {
      final supabase.SupabaseClient client = _requireClient();

      final String? createdBy = client.auth.currentUser?.id;

      final Map<String, dynamic> payload = <String, dynamic>{
        'company_id': companyId,
        'supplier_id': supplierId,
        'amount': amount,
        'payment_method': paymentMethod,
        'payment_date': _formatDate(paymentDate),
        if (purchaseId != null && purchaseId.isNotEmpty)
          'purchase_id': purchaseId,
        if (reference != null && reference.trim().isNotEmpty)
          'reference': reference.trim(),
        if (notes != null && notes.trim().isNotEmpty)
          'notes': notes.trim(),
        if (createdBy != null) 'created_by': createdBy,
      };

      final Map<String, dynamic> row = await client
          .from('supplier_payments')
          .insert(payload)
          .select()
          .single();

      return SupplierPaymentModel.fromMap(row).toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'recordPayment');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'recordPayment');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'recordPayment');
    } on SupplierPaymentException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'recordPayment');
    }
  }

  @override
  Future<void> deletePayment(String paymentId) async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      await client.from('supplier_payments').delete().eq('id', paymentId);
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'deletePayment');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'deletePayment');
    } on SupplierPaymentException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'deletePayment');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static SupplierPaymentException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" (FormatException).',
      error,
      stackTrace,
    );
    return SupplierPaymentException(
      type: SupplierPaymentFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static SupplierPaymentException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final SupplierPaymentFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'SupplierPayment PostgREST error during "$operation" '
      'mapped to ${type.name} (code: ${error.code ?? 'n/a'}).',
    );

    return SupplierPaymentException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static SupplierPaymentException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    return SupplierPaymentException(
      type: SupplierPaymentFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static SupplierPaymentException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final SupplierPaymentFailureType type = _looksLikeNetwork(error)
        ? SupplierPaymentFailureType.network
        : SupplierPaymentFailureType.unknown;

    AppLogger.error(
      'Unhandled supplier-payment error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return SupplierPaymentException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static SupplierPaymentFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    final String message = error.message.toLowerCase();
    final String full = error.toString().toLowerCase();

    if (code == '23514') {
      if (message.contains('amount') || full.contains('amount')) {
        return SupplierPaymentFailureType.invalidAmount;
      }
      if (message.contains('payment_method') ||
          full.contains('payment_method')) {
        return SupplierPaymentFailureType.invalidMethod;
      }
      return SupplierPaymentFailureType.invalidResponse;
    }

    if (code == '23503') {
      if (full.contains('supplier_payments_supplier_company_fk')) {
        return SupplierPaymentFailureType.supplierNotFound;
      }
      if (full.contains('supplier_payments_purchase_company_fk')) {
        return SupplierPaymentFailureType.purchaseNotFound;
      }
      return SupplierPaymentFailureType.notFound;
    }

    if (code == 'PGRST116') {
      return SupplierPaymentFailureType.notFound;
    }
    if (code.startsWith('42501') || code.startsWith('28')) {
      return SupplierPaymentFailureType.unauthorized;
    }
    if (code.startsWith('42')) {
      return SupplierPaymentFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return SupplierPaymentFailureType.unauthorized;
    }

    if (_messageLooksLikeNetwork(message)) {
      return SupplierPaymentFailureType.network;
    }

    return SupplierPaymentFailureType.unknown;
  }

  static bool _looksLikeNetwork(Object error) =>
      _messageLooksLikeNetwork(error.toString().toLowerCase());

  static bool _messageLooksLikeNetwork(String value) {
    return value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection') ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('unreachable') ||
        value.contains('failed host lookup') ||
        value.contains('clientexception');
  }

  // ---------------------------------------------------------------------------
  // Client
  // ---------------------------------------------------------------------------

  supabase.SupabaseClient _requireClient() {
    final supabase.SupabaseClient? client = _client;
    if (client == null) {
      throw const SupplierPaymentException(
        type: SupplierPaymentFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }

  static String _formatDate(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
