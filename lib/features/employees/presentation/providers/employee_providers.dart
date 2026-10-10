// lib/features/employees/presentation/providers/employee_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/employee_remote_datasource.dart';
import '../../data/repositories/employee_repository_impl.dart';
import '../../domain/entities/employee.dart';
import '../../domain/repositories/employee_repository.dart';

final Provider<EmployeeRepository> employeeRepositoryProvider =
    Provider<EmployeeRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return EmployeeRepositoryImpl(EmployeeRemoteDataSource(client));
});

/// Whether to show inactive employees in the list.
class EmployeesIncludeInactiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void setValue(bool value) => state = value;
}

final NotifierProvider<EmployeesIncludeInactiveNotifier, bool>
    employeesIncludeInactiveProvider =
    NotifierProvider<EmployeesIncludeInactiveNotifier, bool>(
  EmployeesIncludeInactiveNotifier.new,
);

/// The list of employees for the current company.
///
/// Note on naming: the method to modify an employee is called
/// [updateEmployee] — never [update] — because `AsyncNotifier` already
/// defines an `update` method with a different signature.
class EmployeesNotifier extends AsyncNotifier<List<Employee>> {
  @override
  Future<List<Employee>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    final bool includeInactive = ref.watch(employeesIncludeInactiveProvider);

    if (companyId == null) return const <Employee>[];

    return ref.read(employeeRepositoryProvider).listEmployees(
          companyId,
          includeInactive: includeInactive,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<Employee> create({
    required String fullName,
    required double baseSalary,
    String? phone,
    String? email,
    String? nationalId,
    String? position,
    DateTime? hireDate,
    String? notes,
    String? companyMemberId,
  }) async {
    final String companyId = _requireCompanyId();
    final Employee created =
        await ref.read(employeeRepositoryProvider).createEmployee(
              companyId: companyId,
              fullName: fullName,
              baseSalary: baseSalary,
              phone: phone,
              email: email,
              nationalId: nationalId,
              position: position,
              hireDate: hireDate,
              notes: notes,
              companyMemberId: companyMemberId,
            );
    await refresh();
    return created;
  }

  Future<Employee> updateEmployee({
    required String employeeId,
    String? fullName,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? nationalId,
    bool clearNationalId = false,
    String? position,
    bool clearPosition = false,
    DateTime? hireDate,
    bool clearHireDate = false,
    double? baseSalary,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
    String? companyMemberId,
    bool clearCompanyMember = false,
  }) async {
    final Employee updated =
        await ref.read(employeeRepositoryProvider).updateEmployee(
              employeeId: employeeId,
              fullName: fullName,
              phone: phone,
              clearPhone: clearPhone,
              email: email,
              clearEmail: clearEmail,
              nationalId: nationalId,
              clearNationalId: clearNationalId,
              position: position,
              clearPosition: clearPosition,
              hireDate: hireDate,
              clearHireDate: clearHireDate,
              baseSalary: baseSalary,
              notes: notes,
              clearNotes: clearNotes,
              isActive: isActive,
              companyMemberId: companyMemberId,
              clearCompanyMember: clearCompanyMember,
            );
    await refresh();
    return updated;
  }

  Future<void> delete(String employeeId) async {
    await ref.read(employeeRepositoryProvider).deleteEmployee(employeeId);
    await refresh();
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const EmployeeException(
        type: EmployeeFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<EmployeesNotifier, List<Employee>>
    employeesProvider =
    AsyncNotifierProvider<EmployeesNotifier, List<Employee>>(
  EmployeesNotifier.new,
);
