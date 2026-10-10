// lib/features/cash/data/datasources/cash_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/cash_repository.dart';

/// Supabase access for the cash register.
///
/// This is the only file in the cash feature that talks to Supabase.
/// Tenant isolation is enforced by RLS via `has_permission(...)`.
class CashRemoteDataSource {
  const CashRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchAccounts(String companyId) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('cash_accounts')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('created_at', ascending: true);
  }

  Future<Map<String, dynamic>> insertAccount({
    required String companyId,
    required String name,
    required String type,
  }) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('cash_accounts')
        .insert(<String, dynamic>{
          'company_id': companyId,
          'name': name,
          'type': type,
        })
        .select()
        .single();
  }

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchCategories(String companyId) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('cash_categories')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('is_system', ascending: false)
        .order('name', ascending: true);
  }

  Future<Map<String, dynamic>> insertCategory({
    required String companyId,
    required String name,
    required String kind,
  }) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('cash_categories')
        .insert(<String, dynamic>{
          'company_id': companyId,
          'name': name,
          'kind': kind,
          'is_system': false,
        })
        .select()
        .single();
  }

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchTransactions({
    required String companyId,
    String? accountId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 100,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('cash_transactions')
        .select()
        .eq('company_id', companyId);

    if (accountId != null) {
      query = query.eq('account_id', accountId);
    }
    if (fromDate != null) {
      query = query.gte('transaction_date', fromDate.toUtc().toIso8601String());
    }
    if (toDate != null) {
      query = query.lte('transaction_date', toDate.toUtc().toIso8601String());
    }

    final List<Map<String, dynamic>> rows = await query
        .order('transaction_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);

    return rows;
  }

  Future<Map<String, dynamic>> insertTransaction({
    required String companyId,
    required String accountId,
    String? branchId,
    String? categoryId,
    required String direction,
    required double amount,
    String? sourceType,
    String? sourceId,
    String? reference,
    String? notes,
    DateTime? transactionDate,
  }) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('cash_transactions')
        .insert(<String, dynamic>{
          'company_id': companyId,
          'account_id': accountId,
          'branch_id': branchId,
          'category_id': categoryId,
          'direction': direction,
          'amount': amount,
          'source_type': sourceType ?? 'manual',
          'source_id': sourceId,
          'reference': reference,
          'notes': notes,
          'transaction_date': transactionDate?.toUtc().toIso8601String(),
        })
        .select()
        .single();
  }

  Future<void> insertSalePayments({
    required String companyId,
    required String saleId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final SupabaseClient client = _requireClient();
    if (rows.isEmpty) return;

    final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[
      for (final Map<String, dynamic> row in rows)
        <String, dynamic>{
          'company_id': companyId,
          'sale_id': saleId,
          'amount': row['amount'],
          'payment_method': row['payment_method'],
        },
    ];

    await client.from('sale_payments').insert(payload);
  }

  // ---------------------------------------------------------------------------
  // Balances — computed via SQL
  // ---------------------------------------------------------------------------

  /// Returns raw balance rows keyed by account_id.
  ///
  /// Uses a lightweight RPC-like query executed inline via `rpc` is not
  /// available; instead we fetch the aggregate through a PostgREST view
  /// created in a follow-up migration. For now the datasource computes the
  /// balance by fetching all transactions — acceptable at the current scale.
  Future<List<Map<String, dynamic>>> fetchAllTransactionsForBalance(
    String companyId,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('cash_transactions')
        .select('account_id, direction, amount')
        .eq('company_id', companyId);
  }

  // ---------------------------------------------------------------------------
  // Client
  // ---------------------------------------------------------------------------

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const CashException(
        type: CashFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }
}
