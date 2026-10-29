// lib/features/cash/presentation/providers/cash_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../companies/presentation/providers/members_providers.dart';
import '../../data/datasources/cash_remote_datasource.dart';
import '../../data/repositories/cash_repository_impl.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/repositories/cash_repository.dart';

/// Cash repository.
final Provider<CashRepository> cashRepositoryProvider =
    Provider<CashRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return CashRepositoryImpl(CashRemoteDataSource(client));
});

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class CashOverviewNotifier extends AsyncNotifier<CashOverview> {
  @override
  Future<CashOverview> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) return const CashOverview.empty();
    return ref.read(cashRepositoryProvider).getOverview(companyId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<CashOverviewNotifier, CashOverview>
    cashOverviewProvider =
    AsyncNotifierProvider<CashOverviewNotifier, CashOverview>(
  CashOverviewNotifier.new,
);

// ---------------------------------------------------------------------------
// Transactions (recent)
// ---------------------------------------------------------------------------

class CashTransactionsNotifier
    extends AsyncNotifier<List<CashTransaction>> {
  @override
  Future<List<CashTransaction>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) return const <CashTransaction>[];
    return ref.read(cashRepositoryProvider).listTransactions(
          companyId: companyId,
          limit: 200,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> addManual({
    required String accountId,
    String? branchId,
    String? categoryId,
    required CashDirection direction,
    required double amount,
    String? reference,
    String? notes,
    DateTime? transactionDate,
  }) async {
    final String companyId = _requireCompanyId();
    await ref.read(cashRepositoryProvider).recordManualTransaction(
          companyId: companyId,
          accountId: accountId,
          branchId: branchId,
          categoryId: categoryId,
          direction: direction,
          amount: amount,
          reference: reference,
          notes: notes,
          transactionDate: transactionDate,
        );
    ref.invalidate(cashOverviewProvider);
    await refresh();
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const CashException(
        type: CashFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<CashTransactionsNotifier, List<CashTransaction>>
    cashTransactionsProvider =
    AsyncNotifierProvider<CashTransactionsNotifier, List<CashTransaction>>(
  CashTransactionsNotifier.new,
);

// ---------------------------------------------------------------------------
// Accounts + Categories
// ---------------------------------------------------------------------------

class CashAccountsNotifier extends AsyncNotifier<List<CashAccount>> {
  @override
  Future<List<CashAccount>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) return const <CashAccount>[];
    return ref.read(cashRepositoryProvider).listAccounts(companyId);
  }

  Future<CashAccount> create({
    required String name,
    required CashAccountType type,
  }) async {
    final String companyId = _requireCompanyId();
    final CashAccount created =
        await ref.read(cashRepositoryProvider).createAccount(
              companyId: companyId,
              name: name,
              type: type,
            );
    ref.invalidateSelf();
    ref.invalidate(cashOverviewProvider);
    await future;
    return created;
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const CashException(
        type: CashFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<CashAccountsNotifier, List<CashAccount>>
    cashAccountsProvider =
    AsyncNotifierProvider<CashAccountsNotifier, List<CashAccount>>(
  CashAccountsNotifier.new,
);

class CashCategoriesNotifier extends AsyncNotifier<List<CashCategory>> {
  @override
  Future<List<CashCategory>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) return const <CashCategory>[];
    return ref.read(cashRepositoryProvider).listCategories(companyId);
  }

  Future<CashCategory> create({
    required String name,
    required CashCategoryKind kind,
  }) async {
    final String companyId = _requireCompanyId();
    final CashCategory created =
        await ref.read(cashRepositoryProvider).createCategory(
              companyId: companyId,
              name: name,
              kind: kind,
            );
    ref.invalidateSelf();
    await future;
    return created;
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const CashException(
        type: CashFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<CashCategoriesNotifier, List<CashCategory>>
    cashCategoriesProvider =
    AsyncNotifierProvider<CashCategoriesNotifier, List<CashCategory>>(
  CashCategoriesNotifier.new,
);

// ---------------------------------------------------------------------------
// ✅ Active Shift (جديد)
// ---------------------------------------------------------------------------

class ActiveShiftNotifier extends AsyncNotifier<Shift?> {
  @override
  Future<Shift?> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) return null;
    return ref.read(cashRepositoryProvider).getActiveShift(companyId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Opens a new shift for the current user.
  ///
  /// Throws if a shift is already open, or if the current user is unknown.
  Future<Shift> openShift({required double openingBalance}) async {
    final String? companyId = ref.read(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      throw const CashException(
        type: CashFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }

    final member = ref.read(currentMemberProvider).valueOrNull;
    if (member == null) {
      throw const CashException(
        type: CashFailureType.unauthorized,
        cause: 'Current member not loaded.',
      );
    }

    final String? branchId = ref.read(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentBranch?.id,
      ),
    );

    final Shift shift = await ref.read(cashRepositoryProvider).openShift(
          companyId: companyId,
          cashierId: member.id,
          branchId: branchId,
          openingBalance: openingBalance,
        );
    await refresh();
    return shift;
  }

  /// Closes the currently active shift.
  Future<Shift> closeShift({
    required double actualClosingBalance,
    String? notes,
  }) async {
    final Shift? current = state.valueOrNull;
    if (current == null) {
      throw const CashException(
        type: CashFailureType.notFound,
        cause: 'No active shift to close.',
      );
    }
    final Shift shift = await ref.read(cashRepositoryProvider).closeShift(
          shiftId: current.id,
          actualClosingBalance: actualClosingBalance,
          notes: notes,
        );
    await refresh();
    // Refresh cash overview and transactions too
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(cashTransactionsProvider);
    return shift;
  }
}

final AsyncNotifierProvider<ActiveShiftNotifier, Shift?>
    activeShiftProvider =
    AsyncNotifierProvider<ActiveShiftNotifier, Shift?>(
  ActiveShiftNotifier.new,
);
