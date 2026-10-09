// lib/features/admin/presentation/providers/admin_companies_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/data/datasources/company_remote_datasource.dart';
import '../../../companies/data/repositories/company_repository_impl.dart';
import '../../../companies/domain/entities/company.dart';
import '../../../companies/domain/repositories/company_repository.dart';

/// Self-contained repository provider for the admin feature.
///
/// Deliberately separate from the regular `CompanyRepository` provider used
/// inside the companies feature: the admin page reads a different result set
/// (`getAllCompanies` vs `getMyCompanies`) and keeping the providers apart
/// avoids polluting the regular tenant context with admin-specific caching.
///
/// `CompanyRepositoryImpl` and `CompanyRemoteDataSource` are both `const`,
/// so creating a second instance costs nothing.
final Provider<CompanyRepository> adminCompanyRepositoryProvider =
    Provider<CompanyRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return CompanyRepositoryImpl(CompanyRemoteDataSource(client));
});

/// Lists every company in the platform (Phase T-2 admin dashboard).
///
/// The result is driven entirely by the RLS policy
/// `companies_platform_admin_select_all`. A non-admin caller receives an
/// empty list. The UI layer adds a proactive check through
/// [isPlatformAdminProvider] to short-circuit the request in that case.
class AdminCompaniesNotifier extends AsyncNotifier<List<Company>> {
  bool _isDisposed = false;

  @override
  Future<List<Company>> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);

    return ref.read(adminCompanyRepositoryProvider).getAllCompanies();
  }

  /// Re-fetches the full list from the server.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Applies a subscription change and patches the in-memory list in place.
  ///
  /// Avoids a full reload: the local update is authoritative because the
  /// server already confirmed the write.
  ///
  /// Throws [CompanyException] when the write fails (network, unauthorized,
  /// or RLS refused the caller because they are not a platform admin).
  Future<Company> updateSubscription({
    required String companyId,
    required String subscriptionStatus,
    String? planId,
    String? billingCycle,
    DateTime? subscribedUntil,
  }) async {
    final Company updated = await ref
        .read(adminCompanyRepositoryProvider)
        .updateCompanySubscription(
          companyId: companyId,
          subscriptionStatus: subscriptionStatus,
          planId: planId,
          billingCycle: billingCycle,
          subscribedUntil: subscribedUntil,
        );

    if (!_isDisposed) {
      final List<Company> current =
          state.valueOrNull ?? const <Company>[];
      state = AsyncData<List<Company>>(<Company>[
        for (final Company c in current)
          if (c.id == updated.id) updated else c,
      ]);
    }

    return updated;
  }
}

final AsyncNotifierProvider<AdminCompaniesNotifier, List<Company>>
    adminCompaniesProvider =
    AsyncNotifierProvider<AdminCompaniesNotifier, List<Company>>(
  AdminCompaniesNotifier.new,
);
