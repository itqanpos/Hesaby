// lib/features/cash/presentation/providers/cash_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../companies/presentation/providers/members_providers.dart';
import '../../data/datasources/cash_remote_datasource.dart';
import '../../data/repositories/cash_repository_impl.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/repositories/cash_repository.dart';

final Provider<CashRepository> cashRepositoryProvider = Provider<CashRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return CashRepositoryImpl(CashRemoteDataSource(client));
});

class CashOverviewNotifier extends AsyncNotifier<CashOverview> {
  @override
  Future<CashOverview> build() async {
    final companyId = ref.watch(companyContextProvider.select((s) => s.currentCompany?.id));
    if (companyId == null) return const CashOverview.empty();
    return ref.read(cashRepositoryProvider).getOverview(companyId);
  }
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
final cashOverviewProvider = AsyncNotifierProvider<CashOverviewNotifier, CashOverview>(CashOverviewNotifier.new);

class CashTransactionsNotifier extends AsyncNotifier<List<CashTransaction>> {
  @override
  Future<List<CashTransaction>> build() async {
    final companyId = ref.watch(companyContextProvider.select((s) => s.currentCompany?.id));
    if (companyId == null) return const <CashTransaction>[];
    return ref.read(cashRepositoryProvider).listTransactions(companyId: companyId, limit: 200);
  }
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
  Future<void> addManual({required String accountId, String? branchId, String? categoryId, required CashDirection direction, required double amount, String? reference, String? notes, DateTime? transactionDate}) async {
    final companyId = _requireCompanyId();
    await ref.read(cashRepositoryProvider).recordManualTransaction(companyId: companyId, accountId: accountId, branchId: branchId, categoryId: categoryId, direction: direction, amount: amount, reference: reference, notes: notes, transactionDate: transactionDate);
    ref.invalidate(cashOverviewProvider);
    await refresh();
  }
  String _requireCompanyId() {
    final id = ref.read(companyContextProvider).currentCompany?.id;
    if (id == null) throw const CashException(type: CashFailureType.unauthorized, cause: 'No company selected.');
    return id;
  }
}
final cashTransactionsProvider = AsyncNotifierProvider<CashTransactionsNotifier, List<CashTransaction>>(CashTransactionsNotifier.new);

class CashAccountsNotifier extends AsyncNotifier<List<CashAccount>> {
  @override
  Future<List<CashAccount>> build() async {
    final companyId = ref.watch(companyContextProvider.select((s) => s.currentCompany?.id));
    if (companyId == null) return const <CashAccount>[];
    return ref.read(cashRepositoryProvider).listAccounts(companyId);
  }
  Future<CashAccount> create({required String name, required CashAccountType type}) async {
    final companyId = ref.read(companyContextProvider).currentCompany?.id;
    if (companyId == null) throw const CashException(type: CashFailureType.unauthorized, cause: 'No company');
    final created = await ref.read(cashRepositoryProvider).createAccount(companyId: companyId, name: name, type: type);
    ref.invalidateSelf();
    ref.invalidate(cashOverviewProvider);
    await future;
    return created;
  }
}
final cashAccountsProvider = AsyncNotifierProvider<CashAccountsNotifier, List<CashAccount>>(CashAccountsNotifier.new);

class CashCategoriesNotifier extends AsyncNotifier<List<CashCategory>> {
  @override
  Future<List<CashCategory>> build() async {
    final companyId = ref.watch(companyContextProvider.select((s) => s.currentCompany?.id));
    if (companyId == null) return const <CashCategory>[];
    return ref.read(cashRepositoryProvider).listCategories(companyId);
  }
  Future<CashCategory> create({required String name, required CashCategoryKind kind}) async {
    final companyId = ref.read(companyContextProvider).currentCompany?.id;
    if (companyId == null) throw const CashException(type: CashFailureType.unauthorized, cause: 'No company');
    final created = await ref.read(cashRepositoryProvider).createCategory(companyId: companyId, name: name, kind: kind);
    ref.invalidateSelf();
    await future;
    return created;
  }
}
final cashCategoriesProvider = AsyncNotifierProvider<CashCategoriesNotifier, List<CashCategory>>(CashCategoriesNotifier.new);

class ActiveShiftNotifier extends AsyncNotifier<Shift?> {
  @override
  Future<Shift?> build() async {
    final companyId = ref.watch(companyContextProvider.select((s) => s.currentCompany?.id));
    if (companyId == null) return null;
    return ref.read(cashRepositoryProvider).getActiveShift(companyId);
  }
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
  Future<Shift> openShift({required double openingBalance}) async {
    final companyId = ref.read(companyContextProvider).currentCompany?.id;
    if (companyId == null) throw const CashException(type: CashFailureType.unauthorized, cause: 'No company');
    final member = ref.read(currentMemberProvider).valueOrNull;
    if (member == null) throw const CashException(type: CashFailureType.unauthorized, cause: 'No member');
    final branchId = ref.read(companyContextProvider).currentBranch?.id;
    final shift = await ref.read(cashRepositoryProvider).openShift(companyId: companyId, cashierId: member.id, branchId: branchId, openingBalance: openingBalance);
    await refresh();
    return shift;
  }
  Future<Shift> closeShift({required double actualClosingBalance, String? notes}) async {
    final current = state.valueOrNull;
    if (current == null) throw const CashException(type: CashFailureType.notFound, cause: 'No active shift');
    final shift = await ref.read(cashRepositoryProvider).closeShift(shiftId: current.id, actualClosingBalance: actualClosingBalance, notes: notes);
    await refresh();
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(cashTransactionsProvider);
    return shift;
  }
}
final activeShiftProvider = AsyncNotifierProvider<ActiveShiftNotifier, Shift?>(ActiveShiftNotifier.new);

final shiftByIdProvider = FutureProvider.family<Shift, String>((ref, String id) async {
  return ref.read(cashRepositoryProvider).getShiftById(id);
});

final shiftTransactionsProvider = FutureProvider.family<List<CashTransaction>, String>((ref, String shiftId) async {
  final companyId = ref.watch(companyContextProvider.select((s) => s.currentCompany?.id));
  if (companyId == null) return const <CashTransaction>[];
  return ref.read(cashRepositoryProvider).listTransactions(companyId: companyId, shiftId: shiftId, limit: 10000);
});
