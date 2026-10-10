// lib/features/expenses/presentation/providers/expense_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../cash/presentation/providers/cash_providers.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/expense_remote_datasource.dart';
import '../../data/repositories/expense_repository_impl.dart';
import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';

final Provider<ExpenseRepository> expenseRepositoryProvider =
    Provider<ExpenseRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return ExpenseRepositoryImpl(ExpenseRemoteDataSource(client));
});

/// Optional date filter for the expenses list.
class ExpenseFilter {
  const ExpenseFilter({this.fromDate, this.toDate});

  final DateTime? fromDate;
  final DateTime? toDate;

  bool get isEmpty => fromDate == null && toDate == null;

  @override
  bool operator ==(Object other) =>
      other is ExpenseFilter &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(fromDate, toDate);
}

class ExpenseFilterNotifier extends Notifier<ExpenseFilter> {
  @override
  ExpenseFilter build() => const ExpenseFilter();

  void setRange(DateTime? from, DateTime? to) {
    state = ExpenseFilter(fromDate: from, toDate: to);
  }

  void clear() {
    state = const ExpenseFilter();
  }
}

final NotifierProvider<ExpenseFilterNotifier, ExpenseFilter>
    expenseFilterProvider =
    NotifierProvider<ExpenseFilterNotifier, ExpenseFilter>(
  ExpenseFilterNotifier.new,
);

/// The list of expenses for the current company.
class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    final ExpenseFilter filter = ref.watch(expenseFilterProvider);

    if (companyId == null) return const <Expense>[];

    return ref.read(expenseRepositoryProvider).listExpenses(
          companyId: companyId,
          fromDate: filter.fromDate,
          toDate: filter.toDate,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<Expense> create({
    String? branchId,
    String? categoryId,
    required String description,
    required double amount,
    required DateTime expenseDate,
    required String paymentMethod,
    String? reference,
    String? notes,
  }) async {
    final String companyId = _requireCompanyId();
    final Expense created =
        await ref.read(expenseRepositoryProvider).createExpense(
              companyId: companyId,
              branchId: branchId,
              categoryId: categoryId,
              description: description,
              amount: amount,
              expenseDate: expenseDate,
              paymentMethod: paymentMethod,
              reference: reference,
              notes: notes,
            );
    // Refresh both the list and the cash register (trigger added a movement).
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(cashTransactionsProvider);
    await refresh();
    return created;
  }

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
    final Expense updated =
        await ref.read(expenseRepositoryProvider).updateExpense(
              expenseId: expenseId,
              categoryId: categoryId,
              clearCategory: clearCategory,
              description: description,
              amount: amount,
              expenseDate: expenseDate,
              paymentMethod: paymentMethod,
              reference: reference,
              clearReference: clearReference,
              notes: notes,
              clearNotes: clearNotes,
            );
    await refresh();
    return updated;
  }

  Future<void> delete(String expenseId) async {
    await ref.read(expenseRepositoryProvider).deleteExpense(expenseId);
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(cashTransactionsProvider);
    await refresh();
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const ExpenseException(
        type: ExpenseFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<ExpensesNotifier, List<Expense>>
    expensesProvider =
    AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(
  ExpensesNotifier.new,
);
