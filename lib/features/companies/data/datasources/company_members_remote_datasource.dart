// lib/features/companies/data/datasources/company_members_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/company_members_repository.dart';
import '../models/company_member_model.dart';

/// Thin wrapper over the Supabase queries for `company_members`.
///
/// Profile data is fetched in a second query and merged in memory, because
/// `company_members.user_id` and `profiles.user_id` both point at
/// `auth.users.id` — PostgREST cannot infer a join between them.
class CompanyMembersRemoteDataSource {
  const CompanyMembersRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  /// Lists every member of [companyId], including inactive ones.
  Future<List<CompanyMemberModel>> listMembers(String companyId) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('company_members')
        .select()
        .eq('company_id', companyId)
        .order('role', ascending: true)
        .order('created_at', ascending: true);

    return _attachProfiles(client, rows);
  }

  /// Returns the row of [userId] in [companyId], or `null`.
  Future<CompanyMemberModel?> getMemberByUser({
    required String companyId,
    required String userId,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic>? row = await client
        .from('company_members')
        .select()
        .eq('company_id', companyId)
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    final List<CompanyMemberModel> enriched =
        await _attachProfiles(client, <Map<String, dynamic>>[row]);
    return enriched.isEmpty ? null : enriched.first;
  }

  /// Updates a member row and returns the fresh model.
  Future<CompanyMemberModel> updateMember({
    required String memberId,
    String? role,
    bool? isActive,
    List<String>? deniedPermissions,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      if (role != null) 'role': role,
      if (isActive != null) 'is_active': isActive,
      if (deniedPermissions != null) 'denied_permissions': deniedPermissions,
    };

    if (payload.isEmpty) {
      throw const MemberException(
        type: MemberFailureType.invalidResponse,
        cause: 'No fields to update.',
      );
    }

    final Map<String, dynamic> row = await client
        .from('company_members')
        .update(payload)
        .eq('id', memberId)
        .select()
        .single();

    final List<CompanyMemberModel> enriched =
        await _attachProfiles(client, <Map<String, dynamic>>[row]);
    if (enriched.isEmpty) {
      throw const MemberException(
        type: MemberFailureType.invalidResponse,
        cause: 'Update succeeded but the returned row is empty.',
      );
    }
    return enriched.first;
  }

  // ---------------------------------------------------------------------------
  // Profile attachment
  // ---------------------------------------------------------------------------

  /// Enriches the given `company_members` rows with their `profiles` row.
  ///
  /// Missing profiles are silently ignored: the entity falls back to
  /// `null` for name and phone in that case.
  Future<List<CompanyMemberModel>> _attachProfiles(
    SupabaseClient client,
    List<Map<String, dynamic>> memberRows,
  ) async {
    if (memberRows.isEmpty) {
      return const <CompanyMemberModel>[];
    }

    final List<String> userIds = memberRows
        .map((Map<String, dynamic> r) => r['user_id'])
        .whereType<String>()
        .toList(growable: false);

    Map<String, Map<String, dynamic>> profilesByUser =
        <String, Map<String, dynamic>>{};

    if (userIds.isNotEmpty) {
      try {
        final List<Map<String, dynamic>> profileRows = await client
            .from('profiles')
            .select('user_id, full_name, phone')
            .inFilter('user_id', userIds);

        profilesByUser = <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> r in profileRows)
            if (r['user_id'] is String) r['user_id'] as String: r,
        };
      } on Object {
        // Non-fatal: if the profiles query fails (e.g. older RLS), we
        // still return the member rows with `null` names.
        profilesByUser = <String, Map<String, dynamic>>{};
      }
    }

    return memberRows.map((Map<String, dynamic> r) {
      final String userId =
          r['user_id'] is String ? r['user_id'] as String : '';
      return CompanyMemberModel.fromMap(
        r,
        profile: profilesByUser[userId],
      );
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Client
  // ---------------------------------------------------------------------------

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const MemberException(
        type: MemberFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }
}
