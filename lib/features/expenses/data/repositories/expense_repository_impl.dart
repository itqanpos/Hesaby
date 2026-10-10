// lib/features/expenses/data/repositories/expense_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';
import '../datasources/expense_remote_datasource.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  const ExpenseRepositoryImpl(this._remote);

  final ExpenseRemoteDataSource _remote;

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('Expense: missing or invalid "$k".');
  }

  static String? _optionalString(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v == null) return null;
    if (v is String) {
      final String t = v.trim();
      return t.isEmpty ? null : t;
    }
    return v.toString();
  }

  static double _double(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return d.toUtc();
    }
    throw FormatException('Expense: "$k" is not a timestamp.');
  }

  static DateTime _requireDate(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is String && v.isNotEmpty) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return DateTime(d.year, d.month, d.day);
    }
    throw FormatException('Expense: "$k" is not a date.');
  }

  static Expense _map(
    Map<String, dynamic> m, {
    String? categoryName,
  }) {
    return Expense(
      id: _requireString(m, 'id'),
      companyId: _requireString(m, 'company_id'),
      branchId: _optionalString(m, 'branch_id'),
      categoryId: _optionalString(m, 'category_id'),
      categoryName: categoryName,
      description: _requireString(m, 'description'),
      amount: _double(m, 'amount'),
      expenseDate: _requireDate(m, 'expense_date'),
      paymentMethod: _requireString(m, 'payment_method'),
      reference: _optionalString(m, 'reference'),
      notes: _optionalString(m, 'notes'),
      createdAt: _requireTimestamp(m, 'created_at'),
      updatedAt: _requireTimestamp(m, 'updated_at'),
    );
  }

  // ---------------------------------------------------------------------------
  // API
  // ---------------------------------------------------------------------------

  @override
  Future<List<Expense>> listExpenses({
    required String companyId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 200,
  }) async {
    try {
      final List<Map<String, dynamic>> rows = await _remote.fetchExpenses(
        companyId: companyId,
        fromDate: fromDate,
        toDate: toDate,
        limit: limit,
      );
      return rows.map((Map<String, dynamic> r) => _map(r)).toList(growable: false);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'listExpenses');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'listExpenses');
    } on ExpenseException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'listExpenses');
    }
  }

  @override
  Future<Expense> createExpense({
    required String companyId,
    String? branchId,
    String? categoryId,
    required String description,
    required double amount,
    required DateTime expenseDate,
    required String paymentMethod,
    String? reference,
    String? notes,
  }) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'company_id': companyId,
        'branch_id': branchId,
        'category_id': categoryId,
        'description': description.trim(),
        'amount': amount,
        'expense_date': expenseDate.toIso8601String().split('T').first,
        'payment_method': paymentMethod,
        'reference': reference,
        'notes': notes,
      };
      final Map<String, dynamic> row = await _remote.insertExpense(payload);
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'createExpense');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'createExpense');
    } on ExpenseException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'createExpense');
    }
  }

  @override
  Future<Expense> updateExpense({
    required String expenseId,
    String? categoryId,
    bool clearCategory = false,
    String? description,
    double? amount,
    DateTime? expenseDate,
    String? paymentMethod,
    String? reference,
    bool clearReference = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    try {
      final Map<String, dynamic> payload = <String, dynamic>{};
      if (clearCategory) {
        payload['category_id'] = null;
      } else if (categoryId != null) {
        payload['category_id'] = categoryId;
      }
      if (description != null) payload['description'] = description.trim();
      if (amount != null) payload['amount'] = amount;
      if (expenseDate != null) {
        payload['expense_date'] =
            expenseDate.toIso8601String().split('T').first;
      }
      if (paymentMethod != null) payload['payment_method'] = paymentMethod;
      if (clearReference) {
        payload['reference'] = null;
      } else if (reference != null) {
        payload['reference'] = reference;
      }
      if (clearNotes) {
        payload['notes'] = null;
      } else if (notes != null) {
        payload['notes'] = notes;
      }

      if (payload.isEmpty) {
        throw const ExpenseException(
          type: ExpenseFailureType.invalidInput,
          cause: 'Empty update payload.',
        );
      }

      final Map<String, dynamic>? row =
          await _remote.updateExpense(expenseId, payload);
      if (row == null) {
        throw const ExpenseException(
          type: ExpenseFailureType.notFound,
          cause: 'Expense not found or update blocked by RLS.',
        );
      }
      return _map(row);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'updateExpense');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'updateExpense');
    } on ExpenseException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'updateExpense');
    }
  }

  @override
  Future<void> deleteExpense(String expenseId) async {
    try {
      await _remote.deleteExpense(expenseId);
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'deleteExpense');
    } on ExpenseException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'deleteExpense');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static ExpenseException _invalidResponse(
    FormatException e,
    StackTrace s,
    String op,
  ) {
    AppLogger.error('Expense invalid response "$op".', e, s);
    return ExpenseException(
      type: ExpenseFailureType.invalidResponse,
      cause: e,
      stackTrace: s,
    );
  }

  static ExpenseException _postgrest(
    supabase.PostgrestException e,
    StackTrace s,
    String op,
  ) {
    final String code = (e.code ?? '').toUpperCase();
    final ExpenseFailureType type;
    if (code.startsWith('42501') || code.startsWith('28')) {
      type = ExpenseFailureType.unauthorized;
    } else if (code.startsWith('23')) {
      type = ExpenseFailureType.invalidInput;
    } else if (code == 'PGRST116') {
      type = ExpenseFailureType.notFound;
    } else {
      type = ExpenseFailureType.unknown;
    }
    AppLogger.warning('Expense PostgREST "$op" → ${type.name} ($code).');
    return ExpenseException(type: type, cause: e, stackTrace: s);
  }

  static ExpenseException _unknown(Object e, StackTrace s, String op) {
    final String desc = e.toString().toLowerCase();
    final ExpenseFailureType type = (desc.contains('socket') ||
            desc.contains('network') ||
            desc.contains('timeout'))
        ? ExpenseFailureType.network
        : ExpenseFailureType.unknown;
    AppLogger.error('Expense unknown error "$op".', e, s);
    return ExpenseException(type: type, cause: e, stackTrace: s);
  }
}
