// lib/features/companies/presentation/providers/company_context_state.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/branch.dart';
import '../../domain/entities/company.dart';
import '../../domain/repositories/company_repository.dart';

/// Lifecycle stage of the company list inside [CompanyContextState].
///
/// Branch loading has its own independent flag
/// ([CompanyContextState.isLoadingBranches]) because it is triggered only
/// after a company has been selected, and must not freeze the company
/// selector while it runs.
enum CompanyContextStatus {
  /// Nothing has been loaded yet.
  initial,

  /// The list of accessible companies is being fetched.
  loadingCompanies,

  /// The list of companies has been resolved. A current company may or may
  /// not be selected, and branches may still be loading.
  ready,

  /// Fetching the list of accessible companies failed.
  error,
}

/// Immutable snapshot of the company/branch selection context.
///
/// The state contains only data: it performs no I/O and holds no backend
/// references. All transitions happen inside the context notifier.
@immutable
class CompanyContextState extends Equatable {
  const CompanyContextState({
    this.status = CompanyContextStatus.initial,
    this.companies = const <Company>[],
    this.currentCompany,
    this.branches = const <Branch>[],
    this.currentBranch,
    this.companiesFailure,
    this.isLoadingBranches = false,
    this.branchesFailure,
  });

  /// Lifecycle stage of the company list.
  final CompanyContextStatus status;

  /// Every company the current user has an active membership in.
  final List<Company> companies;

  /// The currently selected company, or `null` when none is selected.
  final Company? currentCompany;

  /// Branches of [currentCompany] the current user may access.
  final List<Branch> branches;

  /// The currently selected branch, or `null` when none is selected.
  final Branch? currentBranch;

  /// Failure raised while loading the company list, if any.
  final CompanyFailureType? companiesFailure;

  /// Whether branches of [currentCompany] are currently being loaded.
  final bool isLoadingBranches;

  /// Failure raised while loading branches, if any.
  final CompanyFailureType? branchesFailure;

  // ---------------------------------------------------------------------------
  // Status helpers
  // ---------------------------------------------------------------------------

  bool get isInitial => status == CompanyContextStatus.initial;

  bool get isLoadingCompanies => status == CompanyContextStatus.loadingCompanies;

  bool get isReady => status == CompanyContextStatus.ready;

  bool get hasCompaniesError =>
      status == CompanyContextStatus.error && companiesFailure != null;

  // ---------------------------------------------------------------------------
  // Selection helpers
  // ---------------------------------------------------------------------------

  bool get hasCompanies => companies.isNotEmpty;

  bool get hasBranches => branches.isNotEmpty;

  /// The user has no accessible companies at all (loading finished, list is
  /// empty).
  bool get hasNoCompanies =>
      status == CompanyContextStatus.ready && companies.isEmpty;

  /// The user has multiple companies but none is selected yet, so an
  /// explicit selection is required before continuing.
  bool get needsCompanySelection =>
      companies.length > 1 && currentCompany == null;

  /// A company is selected, branch loading has finished, and the company
  /// exposes no accessible branches.
  bool get hasNoBranches =>
      currentCompany != null &&
      !isLoadingBranches &&
      branches.isEmpty &&
      branchesFailure == null;

  /// The user has multiple branches but none is selected yet.
  bool get needsBranchSelection =>
      branches.length > 1 && currentBranch == null;

  /// Whether the context is fully usable: a company is selected and a
  /// branch is selected (or the company has no branches and selection is
  /// therefore not applicable).
  bool get hasCompleteContext =>
      currentCompany != null &&
      (currentBranch != null || (hasNoBranches && branches.isEmpty));

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields are preserved unless an explicit `clear*` flag is set,
  /// so callers can distinguish "leave as is" from "reset to null".
  CompanyContextState copyWith({
    CompanyContextStatus? status,
    List<Company>? companies,
    Company? currentCompany,
    bool clearCurrentCompany = false,
    List<Branch>? branches,
    Branch? currentBranch,
    bool clearCurrentBranch = false,
    CompanyFailureType? companiesFailure,
    bool clearCompaniesFailure = false,
    bool? isLoadingBranches,
    CompanyFailureType? branchesFailure,
    bool clearBranchesFailure = false,
  }) {
    return CompanyContextState(
      status: status ?? this.status,
      companies: companies ?? this.companies,
      currentCompany: clearCurrentCompany
          ? null
          : (currentCompany ?? this.currentCompany),
      branches: branches ?? this.branches,
      currentBranch: clearCurrentBranch
          ? null
          : (currentBranch ?? this.currentBranch),
      companiesFailure: clearCompaniesFailure
          ? null
          : (companiesFailure ?? this.companiesFailure),
      isLoadingBranches: isLoadingBranches ?? this.isLoadingBranches,
      branchesFailure: clearBranchesFailure
          ? null
          : (branchesFailure ?? this.branchesFailure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
        status,
        companies,
        currentCompany,
        branches,
        currentBranch,
        companiesFailure,
        isLoadingBranches,
        branchesFailure,
      ];

  @override
  String toString() =>
      'CompanyContextState(status: ${status.name}, '
      'companies: ${companies.length}, '
      'currentCompany: ${currentCompany?.id}, '
      'branches: ${branches.length}, '
      'currentBranch: ${currentBranch?.id}, '
      'isLoadingBranches: $isLoadingBranches)';
}
