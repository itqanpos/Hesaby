// lib/features/companies/presentation/providers/company_context_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../data/datasources/company_remote_datasource.dart';
import '../../data/repositories/company_repository_impl.dart';
import '../../domain/entities/branch.dart';
import '../../domain/entities/company.dart';
import '../../domain/repositories/company_repository.dart';
import 'company_context_state.dart';

// ============================================================================
// Repository
// ============================================================================

/// The application's company repository.
final Provider<CompanyRepository> companyRepositoryProvider =
    Provider<CompanyRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return CompanyRepositoryImpl(CompanyRemoteDataSource(client));
});

// ============================================================================
// Company context
// ============================================================================

/// Owns the "currently selected company + branch" state.
///
/// All updates route through [CompanyRepository], so RLS on the server
/// enforces tenant isolation and role checks.
class CompanyContextNotifier extends AsyncNotifier<CompanyContextState> {
  @override
  Future<CompanyContextState> build() async {
    final CompanyRepository repo = ref.read(companyRepositoryProvider);
    try {
      final List<Company> companies = await repo.getMyCompanies();
      if (companies.isEmpty) {
        return const CompanyContextState(
          companies: <Company>[],
          currentCompany: null,
          currentBranch: null,
        );
      }

      final Company selected = companies.first;
      final List<Branch> branches =
          await repo.getCompanyBranches(selected.id);
      final Branch? branch = branches.isNotEmpty ? branches.first : null;

      return CompanyContextState(
        companies: companies,
        currentCompany: selected,
        currentBranch: branch,
      );
    } on CompanyException catch (error) {
      return CompanyContextState(
        companies: const <Company>[],
        currentCompany: null,
        currentBranch: null,
        companiesFailure: error.type,
      );
    }
  }

  /// Switches the active company and reloads its branches.
  Future<void> selectCompany(String companyId) async {
    final CompanyContextState? current = state.valueOrNull;
    if (current == null) return;

    final Company? company = current.companies
        .where((Company c) => c.id == companyId)
        .firstOrNull;
    if (company == null) return;

    state = AsyncData<CompanyContextState>(
      current.copyWith(
        currentCompany: company,
        currentBranch: null,
        isLoadingBranches: true,
      ),
    );

    try {
      final List<Branch> branches =
          await ref.read(companyRepositoryProvider).getCompanyBranches(
                companyId,
              );
      state = AsyncData<CompanyContextState>(
        current.copyWith(
          currentCompany: company,
          currentBranch: branches.isNotEmpty ? branches.first : null,
          isLoadingBranches: false,
        ),
      );
    } on CompanyException catch (error) {
      state = AsyncData<CompanyContextState>(
        current.copyWith(
          currentCompany: company,
          currentBranch: null,
          isLoadingBranches: false,
          branchesFailure: error.type,
        ),
      );
    }
  }

  /// Switches the active branch.
  void selectBranch(String branchId) {
    final CompanyContextState? current = state.valueOrNull;
    if (current == null) return;
    final Branch? branch = current.branches
        .where((Branch b) => b.id == branchId)
        .firstOrNull;
    if (branch == null) return;
    state = AsyncData<CompanyContextState>(
      current.copyWith(currentBranch: branch),
    );
  }

  /// Updates the profile of the current company.
  Future<void> updateCurrentCompany({
    required String name,
    required String currency,
    required String timezone,
    String? legalName,
    String? phone,
    String? email,
    String? address,
    String? taxNumber,
    String? commercialRegister,
  }) async {
    final CompanyContextState? current = state.valueOrNull;
    final Company? company = current?.currentCompany;
    if (company == null) {
      throw const CompanyException(
        type: CompanyFailureType.noCompanies,
        cause: 'No current company is selected.',
      );
    }

    final Company updated =
        await ref.read(companyRepositoryProvider).updateCompany(
              companyId: company.id,
              name: name,
              currency: currency,
              timezone: timezone,
              legalName: legalName,
              phone: phone,
              email: email,
              address: address,
              taxNumber: taxNumber,
              commercialRegister: commercialRegister,
            );

    if (current != null) {
      final List<Company> replaced = current.companies
          .map((Company c) => c.id == updated.id ? updated : c)
          .toList(growable: false);
      state = AsyncData<CompanyContextState>(
        current.copyWith(
          companies: replaced,
          currentCompany: updated,
        ),
      );
    }
  }

  /// Reloads companies and branches from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<CompanyContextNotifier, CompanyContextState>
    companyContextProvider =
    AsyncNotifierProvider<CompanyContextNotifier, CompanyContextState>(
  CompanyContextNotifier.new,
);
