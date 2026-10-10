// lib/features/expenses/data/datasources/expense_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/expense_repository.dart';

/// Supabase access for the expenses feature.
class ExpenseRemoteDataSource {
  const ExpenseRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  Future<List<Map<String, dynamic>>> fetchExpenses({
    required String companyId,
    DateTime? fromDate,
    DateTime? toDate,
    required int limit,
  }) async {
    final SupabaseClient client = _requireClient();
    var query = client.from('expenses').select().eq('company_id', companyId);

    if (fromDate != null) {
      query = query.gte(
        'expense_date',
        fromDate.toIso8601String().split('T').first,
      );
    }
    if (toDate != null) {
      query = query.lte(
        'expense_date',
        toDate.toIso8601String().split('T').first,
      );
    }

    final List<Map<String, dynamic>> rows = await query
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows;
  }

  Future<Map<String, dynamic>> insertExpense(
    Map<String, dynamic> payload,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('expenses')
        .insert(payload)
        .select()
        .single();
  }

  Future<Map<String, dynamic>?> updateExpense(
    String expenseId,
    Map<String, dynamic> payload,
  ) async {
    final SupabaseClient client = _requireClient();
    return await client
        .from('expenses')
        .update(payload)
        .eq('id', expenseId)
        .select()
        .maybeSingle();
  }

  Future<void> deleteExpense(String expenseId) async {
    final SupabaseClient client = _requireClient();
    await client.from('expenses').delete().eq('id', expenseId);
  }

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const ExpenseException(
        type: ExpenseFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }
}
