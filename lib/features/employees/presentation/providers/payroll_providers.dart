// lib/features/employees/presentation/providers/payroll_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../cash/presentation/providers/cash_providers.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/employee_payroll_remote_datasource.dart';
import '../../data/repositories/employee_advance_repository_impl.dart';
import '../../data/repositories/employee_salary_repository_impl.dart';
import '../../domain/entities/employee_advance.dart';
import '../../domain/entities/employee_salary.dart';
import '../../domain/repositories/employee_advance_repository.dart';
import '../../domain/repositories/employee_salary_repository.dart';

// ---------------------------------------------------------------------------
// Repositories
// ---------------------------------------------------------------------------

SupabaseClient? _clientOrNull() {
  try {
    return Supabase.instance.client;
  } on Object {
    return null;
  }
}

final Provider<EmployeeAdvanceRepository> advanceRepositoryProvider =
    Provider<EmployeeAdvanceRepository>((ref) {
  return EmployeeAdvanceRepositoryImpl(
    EmployeePayrollRemoteDataSource(_clientOrNull()),
  );
});

final Provider<EmployeeSalaryRepository> salaryRepositoryProvider =
    Provider<EmployeeSalaryRepository>((ref) {
  return EmployeeSalaryRepositoryImpl(
    EmployeePayrollRemoteDataSource(_clientOrNull()),
  );
});

// ---------------------------------------------------------------------------
// Advances — filter & list
// ---------------------------------------------------------------------------

/// When true, the advances list shows only those with `status != deducted`.
class OnlyOpenAdvancesNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
  void setValue(bool value) => state = value;
}

final NotifierProvider<OnlyOpenAdvancesNotifier, bool>
    onlyOpenAdvancesProvider =
    NotifierProvider<OnlyOpenAdvancesNotifier, bool>(
  OnlyOpenAdvancesNotifier.new,
);

class AdvancesNotifier extends AsyncNotifier<List<EmployeeAdvance>> {
  @override
  Future<List<EmployeeAdvance>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    final bool onlyOpen = ref.watch(onlyOpenAdvancesProvider);

    if (companyId == null) return const <EmployeeAdvance>[];

    return ref.read(advanceRepositoryProvider).listAdvances(
          companyId: companyId,
          onlyOpen: onlyOpen,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<EmployeeAdvance> create({
    required String employeeId,
    required double amount,
    required DateTime advanceDate,
    String? reason,
    String? notes,
  }) async {
    final String companyId = _requireCompanyId();
    final EmployeeAdvance created =
        await ref.read(advanceRepositoryProvider).createAdvance(
              companyId: companyId,
              employeeId: employeeId,
              amount: amount,
              advanceDate: advanceDate,
              reason: reason,
              notes: notes,
            );
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(cashTransactionsProvider);
    await refresh();
    return created;
  }

  Future<void> delete(String advanceId) async {
    await ref.read(advanceRepositoryProvider).deleteAdvance(advanceId);
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(cashTransactionsProvider);
    await refresh();
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const AdvanceException(
        type: AdvanceFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<AdvancesNotifier, List<EmployeeAdvance>>
    advancesProvider =
    AsyncNotifierProvider<AdvancesNotifier, List<EmployeeAdvance>>(
  AdvancesNotifier.new,
);

// ---------------------------------------------------------------------------
// Salaries — month selection & list
// ---------------------------------------------------------------------------

/// Currently selected month (first day of month).
class SalaryMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  void setMonth(DateTime month) {
    state = DateTime(month.year, month.month, 1);
  }

  void previous() {
    state = DateTime(state.year, state.month - 1, 1);
  }

  void next() {
    state = DateTime(state.year, state.month + 1, 1);
  }
}

final NotifierProvider<SalaryMonthNotifier, DateTime>
    salaryMonthProvider =
    NotifierProvider<SalaryMonthNotifier, DateTime>(
  SalaryMonthNotifier.new,
);

class SalariesNotifier extends AsyncNotifier<List<EmployeeSalary>> {
  @override
  Future<List<EmployeeSalary>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    final DateTime month = ref.watch(salaryMonthProvider);

    if (companyId == null) return const <EmployeeSalary>[];

    return ref.read(salaryRepositoryProvider).listSalaries(
          companyId: companyId,
          monthStart: month,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<EmployeeSalary> create({
    required String employeeId,
    required DateTime salaryMonth,
    required double baseAmount,
    double bonuses = 0,
    double deductions = 0,
    double advancesDeducted = 0,
    String paymentMethod = 'cash',
    DateTime? paidAt,
    String? notes,
  }) async {
    final String companyId = _requireCompanyId();
    final EmployeeSalary created =
        await ref.read(salaryRepositoryProvider).createSalary(
              companyId: companyId,
              employeeId: employeeId,
              salaryMonth: salaryMonth,
              baseAmount: baseAmount,
              bonuses: bonuses,
              deductions: deductions,
              advancesDeducted: advancesDeducted,
              paymentMethod: paymentMethod,
              paidAt: paidAt,
              notes: notes,
            );
    if (paidAt != null) {
      // Trigger posted a cash movement AND reduced the employee's open
      // advances (by `advancesDeducted`).
      ref.invalidate(cashOverviewProvider);
      ref.invalidate(cashTransactionsProvider);
      ref.invalidate(advancesProvider);
    }
    await refresh();
    return created;
  }

  Future<EmployeeSalary> updateSalary({
    required String salaryId,
    required double baseAmount,
    required double bonuses,
    required double deductions,
    required double advancesDeducted,
    String? paymentMethod,
    String? notes,
    bool clearNotes = false,
  }) async {
    final EmployeeSalary updated =
        await ref.read(salaryRepositoryProvider).updateSalary(
              salaryId: salaryId,
              baseAmount: baseAmount,
              bonuses: bonuses,
              deductions: deductions,
              advancesDeducted: advancesDeducted,
              paymentMethod: paymentMethod,
              notes: notes,
              clearNotes: clearNotes,
            );
    await refresh();
    return updated;
  }

  Future<EmployeeSalary> markPaid({
    required String salaryId,
    String? paymentMethod,
    DateTime? paidAt,
  }) async {
    final EmployeeSalary updated =
        await ref.read(salaryRepositoryProvider).markPaid(
              salaryId: salaryId,
              paymentMethod: paymentMethod,
              paidAt: paidAt,
            );
    // Trigger posted a cash movement AND reduced advances.
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(cashTransactionsProvider);
    ref.invalidate(advancesProvider);
    await refresh();
    return updated;
  }

  Future<void> delete(String salaryId) async {
    await ref.read(salaryRepositoryProvider).deleteSalary(salaryId);
    await refresh();
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const SalaryException(
        type: SalaryFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<SalariesNotifier, List<EmployeeSalary>>
    salariesProvider =
    AsyncNotifierProvider<SalariesNotifier, List<EmployeeSalary>>(
  SalariesNotifier.new,
);
