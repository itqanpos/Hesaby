// lib/features/companies/presentation/providers/company_context_provider.dart

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../../core/storage/preferences_storage.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/company_remote_datasource.dart';
import '../../data/repositories/company_repository_impl.dart';
import '../../domain/entities/branch.dart';
import '../../domain/entities/company.dart';
import '../../domain/repositories/company_repository.dart';
import 'company_context_state.dart';

/// Data source bound to the active Supabase client.
final Provider<CompanyRemoteDataSource> companyRemoteDataSourceProvider =
    Provider<CompanyRemoteDataSource>((ref) {
      SupabaseClient? client;
      try {
        client = Supabase.instance.client;
      } on Object {
        client = null;
      }
      return CompanyRemoteDataSource(client);
    });

/// The application's companies/branches repository.
final Provider<CompanyRepository> companyRepositoryProvider =
    Provider<CompanyRepository>(
      (ref) => CompanyRepositoryImpl(ref.watch(companyRemoteDataSourceProvider)),
    );

/// Provides every branch (active and inactive) of the currently selected
/// company.
final FutureProvider<List<Branch>> companyAllBranchesProvider =
    FutureProvider<List<Branch>>((ref) async {
  final String? companyId = ref.watch(
    companyContextProvider.select(
      (CompanyContextState s) => s.currentCompany?.id,
    ),
  );
  if (companyId == null) {
    return const <Branch>[];
  }
  return ref
      .read(companyRepositoryProvider)
      .getAllCompanyBranches(companyId);
});

/// Owns the company/branch selection context.
class CompanyContextNotifier extends Notifier<CompanyContextState> {
  bool _isDisposed = false;

  static const String _currentCompanyIdKey =
      'hesabi.company_context.current_company_id';

  static const String _currentBranchIdKey =
      'hesabi.company_context.current_branch_id';

  @override
  CompanyContextState build() {
    _isDisposed = false;

    ref.onDispose(() {
      _isDisposed = true;
    });

    ref.listen<AuthState>(authProvider, _onAuthStateChanged);

    final AuthState auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      scheduleMicrotask(_loadFromScratch);
    }

    return const CompanyContextState();
  }

  // ---------------------------------------------------------------------------
  // Public API — selection
  // ---------------------------------------------------------------------------

  Future<void> selectCompany(Company company) async {
    final bool isAuthorized = state.companies.any(
      (Company candidate) => candidate.id == company.id,
    );
    if (!isAuthorized) {
      return;
    }

    final PreferencesStorage preferences = await _preferences();

    await preferences.writeString(
      key: _currentCompanyIdKey,
      value: company.id,
    );
    await preferences.remove(key: _currentBranchIdKey);

    if (_isDisposed) {
      return;
    }

    state = state.copyWith(
      currentCompany: company,
      branches: const <Branch>[],
      clearCurrentBranch: true,
      isLoadingBranches: true,
      clearBranchesFailure: true,
    );

    await _loadBranchesFor(company);
  }

  Future<void> selectBranch(Branch branch) async {
    final Company? currentCompany = state.currentCompany;
    if (currentCompany == null || currentCompany.id != branch.companyId) {
      return;
    }

    final bool isAuthorized = state.branches.any(
      (Branch candidate) => candidate.id == branch.id,
    );
    if (!isAuthorized) {
      return;
    }

    final PreferencesStorage preferences = await _preferences();
    await preferences.writeString(
      key: _currentBranchIdKey,
      value: branch.id,
    );

    if (_isDisposed) {
      return;
    }

    state = state.copyWith(currentBranch: branch);
  }

  Future<void> refresh() => _loadFromScratch();

  Future<void> refreshBranches() async {
    final Company? current = state.currentCompany;
    if (current == null) {
      return;
    }
    if (_isDisposed) {
      return;
    }
    state = state.copyWith(
      isLoadingBranches: true,
      clearBranchesFailure: true,
    );
    await _loadBranchesFor(current);
  }

  // ---------------------------------------------------------------------------
  // Public API — companies
  // ---------------------------------------------------------------------------

  /// Updates the profile of the currently selected company.
  ///
  /// [taxNumber] and [commercialRegister] are optional; passing `null`
  /// clears the corresponding column.
  Future<Company> updateCurrentCompany({
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
    final Company? current = state.currentCompany;
    if (current == null) {
      throw const CompanyException(
        type: CompanyFailureType.unknown,
        cause: 'No company is currently selected.',
      );
    }

    final Company updated =
        await ref.read(companyRepositoryProvider).updateCompany(
              companyId: current.id,
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

    if (_isDisposed) {
      return updated;
    }

    final List<Company> updatedCompanies = state.companies
        .map(
          (Company candidate) =>
              candidate.id == updated.id ? updated : candidate,
        )
        .toList(growable: false);

    state = state.copyWith(
      companies: updatedCompanies,
      currentCompany: updated,
    );

    return updated;
  }

  // ---------------------------------------------------------------------------
  // Public API — branches
  // ---------------------------------------------------------------------------

  Future<Branch> createBranch({
    required String name,
    String? code,
    String? address,
    String? phone,
  }) async {
    final Company? current = state.currentCompany;
    if (current == null) {
      throw const CompanyException(
        type: CompanyFailureType.unknown,
        cause: 'No company is currently selected.',
      );
    }

    final Branch created = await ref
        .read(companyRepositoryProvider)
        .createBranch(
          companyId: current.id,
          name: name,
          code: code,
          address: address,
          phone: phone,
        );

    if (_isDisposed) {
      return created;
    }

    ref.invalidate(companyAllBranchesProvider);
    await refreshBranches();

    return created;
  }

  Future<Branch> updateBranch({
    required String branchId,
    required String name,
    String? code,
    String? address,
    String? phone,
  }) async {
    final Branch updated = await ref
        .read(companyRepositoryProvider)
        .updateBranch(
          branchId: branchId,
          name: name,
          code: code,
          address: address,
          phone: phone,
        );

    if (_isDisposed) {
      return updated;
    }

    final Branch? current = state.currentBranch;
    if (current != null && current.id == updated.id) {
      state = state.copyWith(currentBranch: updated);
    }

    ref.invalidate(companyAllBranchesProvider);
    await refreshBranches();

    return updated;
  }

  Future<Branch> setBranchActive({
    required String branchId,
    required bool isActive,
  }) async {
    final Branch updated = await ref
        .read(companyRepositoryProvider)
        .setBranchActive(
          branchId: branchId,
          isActive: isActive,
        );

    if (_isDisposed) {
      return updated;
    }

    if (!isActive) {
      final Branch? current = state.currentBranch;
      if (current != null && current.id == updated.id) {
        state = state.copyWith(clearCurrentBranch: true);
      }
    }

    ref.invalidate(companyAllBranchesProvider);
    await refreshBranches();

    return updated;
  }

  // ---------------------------------------------------------------------------
  // Internal flows
  // ---------------------------------------------------------------------------

  void _onAuthStateChanged(AuthState? previous, AuthState next) {
    final bool wasAuthenticated = previous?.isAuthenticated ?? false;
    final bool isAuthenticated = next.isAuthenticated;

    if (isAuthenticated && !wasAuthenticated) {
      unawaited(_loadFromScratch());
      return;
    }

    if (!isAuthenticated && wasAuthenticated) {
      unawaited(_resetContext());
    }
  }

  Future<void> _loadFromScratch() async {
    if (_isDisposed) {
      return;
    }

    state = state.copyWith(
      status: CompanyContextStatus.loadingCompanies,
      companies: const <Company>[],
      clearCurrentCompany: true,
      branches: const <Branch>[],
      clearCurrentBranch: true,
      clearCompaniesFailure: true,
      clearBranchesFailure: true,
      isLoadingBranches: false,
    );

    final PreferencesStorage preferences = await _preferences();
    final String? savedCompanyId = await preferences.readString(
      key: _currentCompanyIdKey,
    );
    final String? savedBranchId = await preferences.readString(
      key: _currentBranchIdKey,
    );

    if (_isDisposed) {
      return;
    }

    final List<Company> companies;
    try {
      companies = await ref.read(companyRepositoryProvider).getMyCompanies();
    } on CompanyException catch (error) {
      if (_isDisposed) {
        return;
      }
      state = state.copyWith(
        status: CompanyContextStatus.error,
        companiesFailure: error.type,
      );
      return;
    }

    if (_isDisposed) {
      return;
    }

    if (companies.isEmpty) {
      await preferences.remove(key: _currentCompanyIdKey);
      await preferences.remove(key: _currentBranchIdKey);
      if (_isDisposed) {
        return;
      }
      state = CompanyContextState(
        status: CompanyContextStatus.ready,
        companies: const <Company>[],
      );
      return;
    }

    final Company? selectedCompany = _resolveCompanySelection(
      companies: companies,
      savedCompanyId: savedCompanyId,
    );

    if (selectedCompany == null) {
      await preferences.remove(key: _currentCompanyIdKey);
      await preferences.remove(key: _currentBranchIdKey);
      if (_isDisposed) {
        return;
      }
      state = CompanyContextState(
        status: CompanyContextStatus.ready,
        companies: companies,
      );
      return;
    }

    await preferences.writeString(
      key: _currentCompanyIdKey,
      value: selectedCompany.id,
    );

    if (_isDisposed) {
      return;
    }

    state = CompanyContextState(
      status: CompanyContextStatus.ready,
      companies: companies,
      currentCompany: selectedCompany,
      isLoadingBranches: true,
    );

    await _loadBranchesFor(selectedCompany, savedBranchId: savedBranchId);
  }

  Future<void> _loadBranchesFor(
    Company company, {
    String? savedBranchId,
  }) async {
    final PreferencesStorage preferences = await _preferences();

    final List<Branch> branches;
    try {
      branches = await ref
          .read(companyRepositoryProvider)
          .getCompanyBranches(company.id);
    } on CompanyException catch (error) {
      if (_isDisposed) {
        return;
      }
      if (state.currentCompany?.id != company.id) {
        return;
      }
      state = state.copyWith(
        isLoadingBranches: false,
        branchesFailure: error.type,
      );
      return;
    }

    if (_isDisposed) {
      return;
    }

    if (state.currentCompany?.id != company.id) {
      return;
    }

    final Branch? selectedBranch = _resolveBranchSelection(
      branches: branches,
      savedBranchId: savedBranchId,
    );

    if (selectedBranch != null) {
      await preferences.writeString(
        key: _currentBranchIdKey,
        value: selectedBranch.id,
      );
    } else {
      await preferences.remove(key: _currentBranchIdKey);
    }

    if (_isDisposed) {
      return;
    }

    if (state.currentCompany?.id != company.id) {
      return;
    }

    state = state.copyWith(
      branches: branches,
      currentBranch: selectedBranch,
      clearCurrentBranch: selectedBranch == null,
      isLoadingBranches: false,
      clearBranchesFailure: true,
    );
  }

  Future<void> _resetContext() async {
    final PreferencesStorage preferences = await _preferences();
    await preferences.remove(key: _currentCompanyIdKey);
    await preferences.remove(key: _currentBranchIdKey);

    if (_isDisposed) {
      return;
    }

    state = const CompanyContextState();
  }

  Future<PreferencesStorage> _preferences() =>
      ref.read(preferencesStorageProvider.future);

  // ---------------------------------------------------------------------------
  // Selection resolution
  // ---------------------------------------------------------------------------

  static Company? _resolveCompanySelection({
    required List<Company> companies,
    required String? savedCompanyId,
  }) {
    if (companies.length == 1) {
      return companies.first;
    }
    if (savedCompanyId == null) {
      return null;
    }
    for (final Company company in companies) {
      if (company.id == savedCompanyId) {
        return company;
      }
    }
    return null;
  }

  static Branch? _resolveBranchSelection({
    required List<Branch> branches,
    required String? savedBranchId,
  }) {
    if (branches.length == 1) {
      return branches.first;
    }
    if (savedBranchId == null) {
      return null;
    }
    for (final Branch branch in branches) {
      if (branch.id == savedBranchId) {
        return branch;
      }
    }
    return null;
  }
}

/// Provides the company/branch selection context.
final NotifierProvider<CompanyContextNotifier, CompanyContextState>
companyContextProvider =
    NotifierProvider<CompanyContextNotifier, CompanyContextState>(
      CompanyContextNotifier.new,
    );
