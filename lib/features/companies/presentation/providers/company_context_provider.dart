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
///
/// Falls back to a data source wrapping a `null` client when Supabase was
/// not initialised (for example when credentials were not provided at build
/// time). The data source handles a `null` client gracefully.
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

/// Owns the company/branch selection context.
///
/// Responsibilities:
/// * Load the set of companies the current user may access, then the
///   branches of the selected company, always through the repository (and
///   therefore always under the database's Row Level Security).
/// * Verify locally persisted selections against the freshly loaded,
///   authorized lists before using them. Local storage is never trusted as
///   a source of truth.
/// * React to authentication changes: clear all context on sign-out, and
///   reload from scratch when a user signs in.
///
/// The notifier never accepts a client-supplied identity: the current user
/// is determined by `auth.uid()` inside the database, through RLS.
///
/// Lifecycle safety (Riverpod 2.x):
/// Riverpod 3.x exposes `ref.mounted`, but this project targets Riverpod 2.x.
/// Disposal is tracked with a private flag updated by [Ref.onDispose]. The
/// flag is flipped *inside* a single callback that also cancels the
/// notifier's internal state transitions, so behaviour does not depend on
/// Riverpod's callback ordering. Every write to [state] that can happen
/// after an `await` is guarded by this flag, matching the semantics that
/// `ref.mounted` would provide.
///
/// Build safety:
/// [build] must not write to `state` before returning. The initial load is
/// therefore scheduled on the next microtask with [scheduleMicrotask],
/// which runs *after* Riverpod has stored the value returned by [build].
/// Running the load inline would trigger
/// `StateError: Tried to read the state of an uninitialized provider`,
/// because `_loadFromScratch` reads `state` at its very first statement
/// (before any `await`).
class CompanyContextNotifier extends Notifier<CompanyContextState> {
  bool _isDisposed = false;

  /// Local storage key for the persisted current company identifier.
  static const String _currentCompanyIdKey =
      'hesabi.company_context.current_company_id';

  /// Local storage key for the persisted current branch identifier.
  static const String _currentBranchIdKey =
      'hesabi.company_context.current_branch_id';

  @override
  CompanyContextState build() {
    _isDisposed = false;

    ref.onDispose(() {
      _isDisposed = true;
    });

    // React to sign-in / sign-out without rebuilding this notifier.
    ref.listen<AuthState>(authProvider, _onAuthStateChanged);

    // If the app is already authenticated when this notifier is first
    // created (e.g. a restored session), start loading on the next
    // microtask — never inline, because `_loadFromScratch` writes to
    // `state` before its first `await`.
    final AuthState auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      scheduleMicrotask(_loadFromScratch);
    }

    return const CompanyContextState();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Explicitly selects [company].
  ///
  /// The call is ignored unless [company] is present in the authorized list
  /// currently held by the notifier. Selecting a company clears any current
  /// branch and reloads the branches of the new company.
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

  /// Explicitly selects [branch].
  ///
  /// The call is ignored unless [branch] belongs to the current company and
  /// is present in the authorized branch list held by the notifier.
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

  /// Reloads the entire context from the backend.
  Future<void> refresh() => _loadFromScratch();

  /// Updates the profile of the currently selected company.
  ///
  /// On success the notifier updates the in-memory list and the current
  /// company in place, so every widget that reads
  /// `companyContextProvider.currentCompany` sees the new values without
  /// waiting for a network round-trip on the whole context.
  ///
  /// Throws [CompanyException] when no company is selected or when the
  /// backend rejects the update (typically [CompanyFailureType.unauthorized]
  /// when the caller is not an owner/admin).
  Future<Company> updateCurrentCompany({
    required String name,
    required String currency,
    required String timezone,
    String? legalName,
    String? phone,
    String? email,
    String? address,
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
      // No accessible companies: a valid terminal state, not an error.
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
      // Multiple companies, none selected yet: wait for an explicit choice.
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
      // Ignore results that arrive for a company the user has already
      // navigated away from.
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

  /// Chooses the company that should become current, given the authorized
  /// list and the persisted identifier.
  ///
  /// * A single company is always auto-selected.
  /// * A persisted identifier is honoured only when it matches an entry in
  ///   the authorized list.
  /// * Otherwise `null` is returned and the caller waits for an explicit
  ///   selection.
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

  /// Chooses the branch that should become current, given the authorized
  /// list and the persisted identifier.
  ///
  /// Symmetric to [_resolveCompanySelection], and used only after a company
  /// has been selected.
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
