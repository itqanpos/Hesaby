// lib/features/cash/data/repositories/cash_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/repositories/cash_repository.dart';
import '../datasources/cash_remote_datasource.dart';

class CashRepositoryImpl implements CashRepository {
  const CashRepositoryImpl(this._remote);

  final CashRemoteDataSource _remote;

  // ---------------------------------------------------------------------------
  // Mapping helpers
  // ---------------------------------------------------------------------------

  static String _requireString(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('Cash: missing or invalid "$k".');
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

  static double _requireDouble(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) {
      final double? d = double.tryParse(v);
      if (d != null) return d;
    }
    throw FormatException('Cash: "$k" is not numeric.');
  }

  static bool _optionalBool(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final String l = v.toLowerCase();
      return l == 'true' || l == 't' || l == '1';
    }
    return false;
  }

  static DateTime _requireTimestamp(Map<String, dynamic> m, String k) {
    final Object? v = m[k];
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return d.toUtc();
    }
    throw FormatException('Cash: "$k" is not a timestamp.');
  }

  static CashAccount _mapAccount(Map<String, dynamic> m) {
    return CashAccount(
      id: _requireString(m, 'id'),
      companyId: _requireString(m, 'company_id'),
      name: _requireString(m, 'name'),
      type: CashAccountType.fromString(m['type'] as String?),
      isActive: _optionalBool(m, 'is_active'),
      createdAt: _requireTimestamp(m, 'created_at'),
    );
  }

  static CashCategory _mapCategory(Map<String, dynamic> m) {
    return CashCategory(
      id: _requireString(m, 'id'),
      companyId: _requireString(m, 'company_id'),
      name: _requireString(m, 'name'),
      kind: CashCategoryKind.fromString(m['kind'] as String?),
      isSystem: _optionalBool(m, 'is_system'),
      isActive: _optionalBool(m, 'is_active'),
    );
  }

  static CashTransaction _mapTransaction(
    Map<String, dynamic> m, {
    String? accountName,
    String? categoryName,
  }) {
    return CashTransaction(
      id: _requireString(m, 'id'),
      companyId: _requireString(m, 'company_id'),
      accountId: _requireString(m, 'account_id'),
      accountName: accountName ?? '—',
      branchId: _optionalString(m, 'branch_id'),
      categoryId: _optionalString(m, 'category_id'),
      categoryName: categoryName,
      direction: CashDirection.fromString(m['direction'] as String?),
      amount: _requireDouble(m, 'amount'),
      sourceType: _requireString(m, 'source_type'),
      sourceId: _optionalString(m, 'source_id'),
      reference: _optionalString(m, 'reference'),
      notes: _optionalString(m, 'notes'),
      transactionDate: _requireTimestamp(m, 'transaction_date'),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  @override
  Future<List<CashAccount>> listAccounts(String companyId) async {
    try {
      final List<Map<String, dynamic>> rows =
          await _remote.fetchAccounts(companyId);
      return rows.map(_mapAccount).toList(growable: false);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'listAccounts');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'listAccounts');
    } on CashException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'listAccounts');
    }
  }

  @override
  Future<List<CashCategory>> listCategories(String companyId) async {
    try {
      final List<Map<String, dynamic>> rows =
          await _remote.fetchCategories(companyId);
      return rows.map(_mapCategory).toList(growable: false);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'listCategories');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'listCategories');
    } on CashException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'listCategories');
    }
  }

  @override
  Future<CashOverview> getOverview(String companyId) async {
    try {
      final List<CashAccount> accounts = await listAccounts(companyId);
      if (accounts.isEmpty) {
        return const CashOverview.empty();
      }

      final List<Map<String, dynamic>> txRows =
          await _remote.fetchAllTransactionsForBalance(companyId);

      final Map<String, double> balanceByAccount = <String, double>{};
      for (final Map<String, dynamic> row in txRows) {
        final String accountId = row['account_id'] as String;
        final String direction = row['direction'] as String;
        final double amount = _parseNum(row['amount']);
        final double signed = direction == 'in' ? amount : -amount;
        balanceByAccount[accountId] =
            (balanceByAccount[accountId] ?? 0) + signed;
      }

      final List<CashAccountBalance> balances = <CashAccountBalance>[
        for (final CashAccount a in accounts)
          CashAccountBalance(
            account: a,
            balance: balanceByAccount[a.id] ?? 0,
          ),
      ];

      final double total = balances.fold<double>(
        0,
        (double sum, CashAccountBalance b) => sum + b.balance,
      );

      return CashOverview(balances: balances, totalBalance: total);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'getOverview');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'getOverview');
    } on CashException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'getOverview');
    }
  }

  static double _parseNum(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Future<List<CashTransaction>> listTransactions({
    required String companyId,
    String? accountId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 100,
  }) async {
    try {
      final List<Map<String, dynamic>> rows =
          await _remote.fetchTransactions(
        companyId: companyId,
        accountId: accountId,
        fromDate: fromDate,
        toDate: toDate,
        limit: limit,
      );

      // Resolve account and category names in bulk.
      final List<CashAccount> accounts = await listAccounts(companyId);
      final List<CashCategory> categories = await listCategories(companyId);

      final Map<String, String> accountNames = <String, String>{
        for (final CashAccount a in accounts) a.id: a.name,
      };
      final Map<String, String> categoryNames = <String, String>{
        for (final CashCategory c in categories) c.id: c.name,
      };

      return <CashTransaction>[
        for (final Map<String, dynamic> row in rows)
          _mapTransaction(
            row,
            accountName: accountNames[row['account_id']],
            categoryName: row['category_id'] == null
                ? null
                : categoryNames[row['category_id']],
          ),
      ];
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'listTransactions');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'listTransactions');
    } on CashException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'listTransactions');
    }
  }

  @override
  Future<void> recordSalePayments({
    required String companyId,
    required String saleId,
    required List<SalePaymentDraft> payments,
  }) async {
    if (payments.isEmpty) return;
    try {
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        for (final SalePaymentDraft p in payments)
          <String, dynamic>{
            'amount': p.amount,
            'payment_method': p.method,
          },
      ];
      await _remote.insertSalePayments(
        companyId: companyId,
        saleId: saleId,
        rows: rows,
      );
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'recordSalePayments');
    } on CashException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'recordSalePayments');
    }
  }

  @override
  Future<CashTransaction> recordManualTransaction({
    required String companyId,
    required String accountId,
    String? branchId,
    String? categoryId,
    required CashDirection direction,
    required double amount,
    String? reference,
    String? notes,
    DateTime? transactionDate,
  }) async {
    if (amount <= 0) {
      throw const CashException(
        type: CashFailureType.invalidInput,
        cause: 'Amount must be positive.',
      );
    }
    try {
      final Map<String, dynamic> row = await _remote.insertTransaction(
        companyId: companyId,
        accountId: accountId,
        branchId: branchId,
        categoryId: categoryId,
        direction: direction.value,
        amount: amount,
        sourceType: 'manual',
        reference: reference,
        notes: notes,
        transactionDate: transactionDate,
      );
      final List<CashAccount> accounts = await listAccounts(companyId);
      final String? name = accounts
          .cast<CashAccount?>()
          .firstWhere((CashAccount? a) => a?.id == accountId, orElse: () => null)
          ?.name;
      return _mapTransaction(row, accountName: name);
    } on FormatException catch (e, s) {
      throw _invalidResponse(e, s, 'recordManualTransaction');
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'recordManualTransaction');
    } on CashException {
      rethrow;
    } on Object catch (e, s) {
      throw _unknown(e, s, 'recordManualTransaction');
    }
  }

  @override
  Future<CashAccount> createAccount({
    required String companyId,
    required String name,
    required CashAccountType type,
  }) async {
    try {
      final Map<String, dynamic> row = await _remote.insertAccount(
        companyId: companyId,
        name: name.trim(),
        type: type.name,
      );
      return _mapAccount(row);
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'createAccount');
    } on Object catch (e, s) {
      throw _unknown(e, s, 'createAccount');
    }
  }

  @override
  Future<CashCategory> createCategory({
    required String companyId,
    required String name,
    required CashCategoryKind kind,
  }) async {
    try {
      final Map<String, dynamic> row = await _remote.insertCategory(
        companyId: companyId,
        name: name.trim(),
        kind: kind.name,
      );
      return _mapCategory(row);
    } on supabase.PostgrestException catch (e, s) {
      throw _postgrest(e, s, 'createCategory');
    } on Object catch (e, s) {
      throw _unknown(e, s, 'createCategory');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static CashException _invalidResponse(
    FormatException e,
    StackTrace s,
    String op,
  ) {
    AppLogger.error('Cash invalid response "$op".', e, s);
    return CashException(
      type: CashFailureType.invalidResponse,
      cause: e,
      stackTrace: s,
    );
  }

  static CashException _postgrest(
    supabase.PostgrestException e,
    StackTrace s,
    String op,
  ) {
    final String code = (e.code ?? '').toUpperCase();
    final CashFailureType type;
    if (code.startsWith('42501') || code.startsWith('28')) {
      type = CashFailureType.unauthorized;
    } else if (code.startsWith('23')) {
      type = CashFailureType.invalidInput;
    } else if (code == 'PGRST116') {
      type = CashFailureType.notFound;
    } else {
      type = CashFailureType.unknown;
    }
    AppLogger.warning('Cash PostgREST "$op" → ${type.name} ($code).');
    return CashException(type: type, cause: e, stackTrace: s);
  }

  static CashException _unknown(Object e, StackTrace s, String op) {
    final String desc = e.toString().toLowerCase();
    final CashFailureType type = (desc.contains('socket') ||
            desc.contains('network') ||
            desc.contains('timeout'))
        ? CashFailureType.network
        : CashFailureType.unknown;
    AppLogger.error('Cash unknown error "$op".', e, s);
    return CashException(type: type, cause: e, stackTrace: s);
  }
}
