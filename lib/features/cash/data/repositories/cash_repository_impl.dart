// lib/features/cash/data/repositories/cash_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../../../../core/utils/logger.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/repositories/cash_repository.dart';
import '../datasources/cash_remote_datasource.dart';

class CashRepositoryImpl implements CashRepository {
  const CashRepositoryImpl(this._remote);
  final CashRemoteDataSource _remote;

  static String _requireString(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is String && v.isNotEmpty) return v;
    throw FormatException('Cash: missing or invalid "$k".');
  }
  static String? _optionalString(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is String) return v.trim().isEmpty ? null : v.trim();
    return v.toString();
  }
  static double _requireDouble(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is num) return v.toDouble();
    if (v is String) {
      final d = double.tryParse(v);
      if (d != null) return d;
    }
    throw FormatException('Cash: "$k" is not numeric.');
  }
  static double? _optionalDouble(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
  static bool _optionalBool(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }
  static DateTime _requireTimestamp(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is DateTime) return v.toUtc();
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return d.toUtc();
    }
    throw FormatException('Cash: "$k" is not a timestamp.');
  }
  static DateTime? _optionalTimestamp(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v == null) return null;
    if (v is DateTime) return v.toUtc();
    if (v is String) return DateTime.tryParse(v)?.toUtc();
    return null;
  }

  static CashAccount _mapAccount(Map<String, dynamic> m) => CashAccount(
    id: _requireString(m, 'id'), companyId: _requireString(m, 'company_id'), name: _requireString(m, 'name'),
    type: CashAccountType.fromString(m['type']), isActive: _optionalBool(m, 'is_active'), createdAt: _requireTimestamp(m, 'created_at'),
  );

  static CashCategory _mapCategory(Map<String, dynamic> m) => CashCategory(
    id: _requireString(m, 'id'), companyId: _requireString(m, 'company_id'), name: _requireString(m, 'name'),
    kind: CashCategoryKind.fromString(m['kind']), isSystem: _optionalBool(m, 'is_system'), isActive: _optionalBool(m, 'is_active'),
  );

  static CashTransaction _mapTransaction(Map<String, dynamic> m, {String? accountName, String? categoryName}) => CashTransaction(
    id: _requireString(m, 'id'), companyId: _requireString(m, 'company_id'), accountId: _requireString(m, 'account_id'),
    accountName: accountName ?? '—', shiftId: _optionalString(m, 'shift_id'), branchId: _optionalString(m, 'branch_id'),
    categoryId: _optionalString(m, 'category_id'), categoryName: categoryName,
    direction: CashDirection.fromString(m['direction']), amount: _requireDouble(m, 'amount'),
    sourceType: _requireString(m, 'source_type'), sourceId: _optionalString(m, 'source_id'),
    reference: _optionalString(m, 'reference'), notes: _optionalString(m, 'notes'), transactionDate: _requireTimestamp(m, 'transaction_date'),
  );

  static Shift _mapShift(Map<String, dynamic> m) => Shift(
    id: _requireString(m, 'id'), companyId: _requireString(m, 'company_id'), cashierId: _requireString(m, 'cashier_id'),
    branchId: _optionalString(m, 'branch_id'), openedAt: _requireTimestamp(m, 'opened_at'), closedAt: _optionalTimestamp(m, 'closed_at'),
    openingBalance: _requireDouble(m, 'opening_balance'), expectedClosingBalance: _optionalDouble(m, 'expected_closing_balance'),
    actualClosingBalance: _optionalDouble(m, 'actual_closing_balance'), difference: _optionalDouble(m, 'difference'),
    status: _requireString(m, 'status'), notes: _optionalString(m, 'notes'),
  );

  @override
  Future<List<CashAccount>> listAccounts(String companyId) async {
    try {
      return (await _remote.fetchAccounts(companyId)).map(_mapAccount).toList();
    } catch (e, s) { throw _unknown(e, s, 'listAccounts'); }
  }

  @override
  Future<List<CashCategory>> listCategories(String companyId) async {
    try {
      return (await _remote.fetchCategories(companyId)).map(_mapCategory).toList();
    } catch (e, s) { throw _unknown(e, s, 'listCategories'); }
  }

  @override
  Future<CashOverview> getOverview(String companyId) async {
    try {
      final accounts = await listAccounts(companyId);
      if (accounts.isEmpty) return const CashOverview.empty();
      final txRows = await _remote.fetchAllTransactionsForBalance(companyId);
      final balances = <String, double>{};
      for (var row in txRows) {
        final accId = row['account_id'] as String;
        final dir = row['direction'] as String;
        final amt = _parseNum(row['amount']);
        balances[accId] = (balances[accId] ?? 0) + (dir == 'in' ? amt : -amt);
      }
      final result = [for (var a in accounts) CashAccountBalance(account: a, balance: balances[a.id] ?? 0)];
      return CashOverview(balances: result, totalBalance: result.fold(0, (s, b) => s + b.balance));
    } catch (e, s) { throw _unknown(e, s, 'getOverview'); }
  }

  double _parseNum(dynamic v) => v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);

  @override
  Future<List<CashTransaction>> listTransactions({required String companyId, String? accountId, String? shiftId, DateTime? fromDate, DateTime? toDate, int limit = 100}) async {
    try {
      final rows = await _remote.fetchTransactions(companyId: companyId, accountId: accountId, shiftId: shiftId, fromDate: fromDate, toDate: toDate, limit: limit);
      final accounts = await listAccounts(companyId);
      final categories = await listCategories(companyId);
      final accNames = {for (var a in accounts) a.id: a.name};
      final catNames = {for (var c in categories) c.id: c.name};
      return [for (var r in rows) _mapTransaction(r, accountName: accNames[r['account_id']], categoryName: r['category_id'] == null ? null : catNames[r['category_id']])];
    } catch (e, s) { throw _unknown(e, s, 'listTransactions'); }
  }

  @override
  Future<void> recordSalePayments({required String companyId, required String saleId, required List<SalePaymentDraft> payments}) async {
    if (payments.isEmpty) return;
    try {
      await _remote.insertSalePayments(companyId: companyId, saleId: saleId, rows: [for (var p in payments) {'amount': p.amount, 'payment_method': p.method}]);
    } catch (e, s) { throw _unknown(e, s, 'recordSalePayments'); }
  }

  @override
  Future<CashTransaction> recordManualTransaction({required String companyId, required String accountId, String? branchId, String? categoryId, required CashDirection direction, required double amount, String? reference, String? notes, DateTime? transactionDate}) async {
    if (amount <= 0) throw const CashException(type: CashFailureType.invalidInput, cause: 'Amount must be positive.');
    try {
      final row = await _remote.insertTransaction(companyId: companyId, accountId: accountId, branchId: branchId, categoryId: categoryId, direction: direction.value, amount: amount, sourceType: 'manual', reference: reference, notes: notes, transactionDate: transactionDate);
      final accounts = await listAccounts(companyId);
      return _mapTransaction(row, accountName: accounts.firstWhere((a) => a.id == accountId, orElse: () => accounts.first).name);
    } catch (e, s) { throw _unknown(e, s, 'recordManualTransaction'); }
  }

  @override
  Future<CashAccount> createAccount({required String companyId, required String name, required CashAccountType type}) async {
    try {
      return _mapAccount(await _remote.insertAccount(companyId: companyId, name: name.trim(), type: type.name));
    } catch (e, s) { throw _unknown(e, s, 'createAccount'); }
  }

  @override
  Future<CashCategory> createCategory({required String companyId, required String name, required CashCategoryKind kind}) async {
    try {
      return _mapCategory(await _remote.insertCategory(companyId: companyId, name: name.trim(), kind: kind.name));
    } catch (e, s) { throw _unknown(e, s, 'createCategory'); }
  }

  @override
  Future<Shift?> getActiveShift(String companyId) async {
    try {
      final row = await _remote.fetchActiveShift(companyId);
      return row == null ? null : _mapShift(row);
    } catch (e, s) { throw _unknown(e, s, 'getActiveShift'); }
  }

  @override
  Future<Shift> getShiftById(String shiftId) async {
    try {
      return _mapShift(await _remote.fetchShiftById(shiftId));
    } catch (e, s) { throw _unknown(e, s, 'getShiftById'); }
  }

  @override
  Future<Shift> openShift({required String companyId, required String cashierId, String? branchId, required double openingBalance}) async {
    try {
      return _mapShift(await _remote.insertShift(companyId: companyId, cashierId: cashierId, branchId: branchId, openingBalance: openingBalance));
    } catch (e, s) { throw _unknown(e, s, 'openShift'); }
  }

  @override
  Future<Shift> closeShift({required String shiftId, required double actualClosingBalance, String? notes}) async {
    try {
      final current = await _remote.fetchShiftById(shiftId);
      final opening = _requireDouble(current, 'opening_balance');
      final openedAt = _requireTimestamp(current, 'opened_at');
      final companyId = _requireString(current, 'company_id');
      
      final txRows = await _remote.fetchTransactions(companyId: companyId, shiftId: shiftId, fromDate: openedAt, limit: 10000);
      double netMovement = 0;
      for (var row in txRows) {
        final dir = row['direction'] as String;
        final amt = _parseNum(row['amount']);
        netMovement += dir == 'in' ? amt : -amt;
      }
      final expected = opening + netMovement;
      return _mapShift(await _remote.updateShiftClose(shiftId: shiftId, actualClosingBalance: actualClosingBalance, expectedClosingBalance: expected, notes: notes));
    } catch (e, s) { throw _unknown(e, s, 'closeShift'); }
  }

  static CashException _unknown(Object e, StackTrace s, String op) {
    final desc = e.toString().toLowerCase();
    final type = (desc.contains('socket') || desc.contains('network') || desc.contains('timeout')) ? CashFailureType.network : CashFailureType.unknown;
    AppLogger.error('Cash unknown error "$op".', e, s);
    return CashException(type: type, cause: e, stackTrace: s);
  }
}
