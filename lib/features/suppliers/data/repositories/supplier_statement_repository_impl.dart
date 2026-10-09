// lib/features/suppliers/data/repositories/supplier_statement_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/entities/supplier_statement.dart';
import '../../domain/repositories/supplier_statement_repository.dart';
import '../models/supplier_model.dart';

/// Concrete implementation of [SupplierStatementRepository] backed by
/// Supabase.
///
/// Approach:
/// * Fetch the supplier row.
/// * Fetch every **confirmed** purchase of the supplier (draft and
///   cancelled rows do not affect the running balance).
/// * Fetch every payment made to the supplier.
/// * Build entries, split them by the requested window, and let
///   [SupplierStatement.build] compute the running balance.
///
/// The two source queries are intentionally not filtered by date so that
/// the opening balance can be computed without a third round-trip.
class SupplierStatementRepositoryImpl
    implements SupplierStatementRepository {
  const SupplierStatementRepositoryImpl(this._client);

  final supabase.SupabaseClient? _client;

  @override
  Future<SupplierStatement> buildStatement({
    required String supplierId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final supabase.SupabaseClient client = _requireClient();

      // ---- Supplier row --------------------------------------------------
      final Map<String, dynamic> supplierRow = await client
          .from('suppliers')
          .select()
          .eq('id', supplierId)
          .single();
      final Supplier supplier =
          SupplierModel.fromMap(supplierRow).toEntity();

      // ---- Purchases (confirmed only) -----------------------------------
      final List<Map<String, dynamic>> purchaseRows = await client
          .from('purchases')
          .select(
            'id, purchase_date, invoice_number, total, notes',
          )
          .eq('supplier_id', supplierId)
          .eq('status', 'confirmed')
          .order('purchase_date', ascending: true);

      // ---- Payments ------------------------------------------------------
      final List<Map<String, dynamic>> paymentRows = await client
          .from('supplier_payments')
          .select(
            'id, payment_date, reference, notes, amount, payment_method',
          )
          .eq('supplier_id', supplierId)
          .order('payment_date', ascending: true);

      // ---- Combine into entries -----------------------------------------
      final List<SupplierStatementEntry> allEntries =
          <SupplierStatementEntry>[];

      for (final Map<String, dynamic> row in purchaseRows) {
        allEntries.add(
          SupplierStatementEntry(
            id: _asString(row['id']),
            type: SupplierStatementEntryType.purchase,
            date: _asDate(row['purchase_date']),
            debit: _asDouble(row['total']),
            credit: 0,
            reference: _asNullableString(row['invoice_number']),
            description: 'فاتورة مشتريات',
            notes: _asNullableString(row['notes']),
          ),
        );
      }

      for (final Map<String, dynamic> row in paymentRows) {
        allEntries.add(
          SupplierStatementEntry(
            id: _asString(row['id']),
            type: SupplierStatementEntryType.payment,
            date: _asDate(row['payment_date']),
            debit: 0,
            credit: _asDouble(row['amount']),
            reference: _asNullableString(row['reference']),
            description: 'دفعة',
            notes: _asNullableString(row['notes']),
          ),
        );
      }

      // ---- Split by window ----------------------------------------------
      final DateTime? from = fromDate;
      final DateTime? to = toDate;

      double openingBalance = 0;
      final List<SupplierStatementEntry> windowed =
          <SupplierStatementEntry>[];

      for (final SupplierStatementEntry entry in allEntries) {
        if (from != null && entry.date.isBefore(from)) {
          openingBalance += entry.debit - entry.credit;
          continue;
        }
        if (to != null && entry.date.isAfter(to)) {
          continue;
        }
        windowed.add(entry);
      }

      return SupplierStatement.build(
        supplier: supplier,
        entries: windowed,
        openingBalance: openingBalance,
        fromDate: fromDate,
        toDate: toDate,
      );
    } on FormatException catch (error, stackTrace) {
      AppLogger.error(
        'Invalid response building supplier statement',
        error,
        stackTrace,
      );
      throw SupplierStatementException(
        type: SupplierStatementFailureType.invalidResponse,
        cause: error,
        stackTrace: stackTrace,
      );
    } on supabase.PostgrestException catch (error, stackTrace) {
      AppLogger.warning(
        'PostgREST error building supplier statement '
        '(code: ${error.code ?? 'n/a'}).',
      );
      throw SupplierStatementException(
        type: _classify(error),
        cause: error,
        stackTrace: stackTrace,
      );
    } on supabase.AuthException catch (error, stackTrace) {
      throw SupplierStatementException(
        type: SupplierStatementFailureType.unauthorized,
        cause: error,
        stackTrace: stackTrace,
      );
    } on SupplierStatementException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Unhandled error building supplier statement',
        error,
        stackTrace,
      );
      throw SupplierStatementException(
        type: SupplierStatementFailureType.unknown,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  supabase.SupabaseClient _requireClient() {
    final supabase.SupabaseClient? client = _client;
    if (client == null) {
      throw const SupplierStatementException(
        type: SupplierStatementFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }

  static SupplierStatementFailureType _classify(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    if (code == 'PGRST116') {
      return SupplierStatementFailureType.notFound;
    }
    if (code.startsWith('42501') || code.startsWith('28')) {
      return SupplierStatementFailureType.unauthorized;
    }
    if (code.startsWith('42')) {
      return SupplierStatementFailureType.invalidResponse;
    }
    return SupplierStatementFailureType.unknown;
  }

  static String _asString(Object? value) {
    if (value is String) return value;
    return value?.toString() ?? '';
  }

  static String? _asNullableString(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final String t = value.trim();
      return t.isEmpty ? null : t;
    }
    return value.toString();
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime _asDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.now().toUtc();
  }
}
