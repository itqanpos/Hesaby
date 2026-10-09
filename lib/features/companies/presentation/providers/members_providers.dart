// lib/features/companies/presentation/providers/members_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/company_members_remote_datasource.dart';
import '../../data/repositories/company_members_repository_impl.dart';
import '../../domain/entities/company_member.dart';
import '../../domain/repositories/company_members_repository.dart';
import 'company_context_provider.dart';
import 'company_context_state.dart';

// ============================================================================
// Repository
// ============================================================================

/// The application's company-members repository.
final Provider<CompanyMembersRepository> membersRepositoryProvider =
    Provider<CompanyMembersRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return CompanyMembersRepositoryImpl(
    CompanyMembersRemoteDataSource(client),
  );
});

// ============================================================================
// Members list — for the management page
// ============================================================================

/// Lists every member of the currently selected company.
///
/// Only accessible to owner/admin/manager (RLS). Errors surface as
/// [MemberException]; the UI can map them to localized messages.
class MembersNotifier extends AsyncNotifier<List<CompanyMember>> {
  bool _isDisposed = false;

  @override
  Future<List<CompanyMember>> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);

    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return const <CompanyMember>[];
    }

    return ref.read(membersRepositoryProvider).listMembers(companyId);
  }

  /// Updates a single member and refreshes the list.
  Future<CompanyMember> updateMember({
    required String memberId,
    String? role,
    bool? isActive,
    List<String>? deniedPermissions,
  }) async {
    final CompanyMember updated =
        await ref.read(membersRepositoryProvider).updateMember(
              memberId: memberId,
              role: role,
              isActive: isActive,
              deniedPermissions: deniedPermissions,
            );

    if (!_isDisposed) {
      // Optimistic in-place refresh, then re-fetch to stay in sync.
      final List<CompanyMember>? current = state.valueOrNull;
      if (current != null) {
        state = AsyncData<List<CompanyMember>>(
          current
              .map((CompanyMember m) => m.id == updated.id ? updated : m)
              .toList(growable: false),
        );
      }
      ref.invalidateSelf();
      // Also refresh the current member, in case the edited row was the
      // caller's own membership (self-edit of role/permissions).
      ref.invalidate(currentMemberProvider);
    }

    return updated;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<MembersNotifier, List<CompanyMember>>
    membersProvider =
    AsyncNotifierProvider<MembersNotifier, List<CompanyMember>>(
  MembersNotifier.new,
);

// ============================================================================
// Current member — for permission checks
// ============================================================================

/// Returns the [CompanyMember] row of the currently authenticated user in
/// the currently selected company, or `null` when there is no active
/// company / session.
///
/// This is the source of truth for every permission check in the app.
class CurrentMemberNotifier extends AsyncNotifier<CompanyMember?> {
  @override
  Future<CompanyMember?> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    final String? userId = ref.watch(
      authProvider.select((AuthState s) => s.session?.userId),
    );

    if (companyId == null || userId == null) {
      return null;
    }

    return ref.read(membersRepositoryProvider).getMemberByUser(
          companyId: companyId,
          userId: userId,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<CurrentMemberNotifier, CompanyMember?>
    currentMemberProvider =
    AsyncNotifierProvider<CurrentMemberNotifier, CompanyMember?>(
  CurrentMemberNotifier.new,
);

// ============================================================================
// Permission checks
// ============================================================================

/// Whether the current user holds [code].
///
/// Safe default: returns `false` when the current member is unknown
/// (during loading, unauthenticated, or when no company is selected).
/// Use [permissionsLoadingProvider] when you need to distinguish
/// "loading" from "denied".
final hasPermissionProvider = Provider.family<bool, String>((ref, String code) {
  final AsyncValue<CompanyMember?> memberAsync =
      ref.watch(currentMemberProvider);
  final CompanyMember? member = memberAsync.valueOrNull;
  if (member == null) {
    return false;
  }
  return member.hasPermission(code);
});

/// Whether the current permissions are still being loaded. UI can use this
/// to hide actions during loading rather than flashing them off then on.
final Provider<bool> permissionsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(currentMemberProvider).isLoading;
});

/// Convenience: whether the current user is an owner, admin, or manager.
final Provider<bool> isManagerProvider = Provider<bool>((ref) {
  final CompanyMember? member = ref.watch(currentMemberProvider).valueOrNull;
  return member?.canManageMembers ?? false;
});

/// Convenience: whether the current user is an owner.
final Provider<bool> isOwnerProvider = Provider<bool>((ref) {
  final CompanyMember? member = ref.watch(currentMemberProvider).valueOrNull;
  return member?.isOwner ?? false;
});
