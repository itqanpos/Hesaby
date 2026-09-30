// lib/features/companies/data/datasources/company_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/company_repository.dart';
import '../models/branch_model.dart';
import '../models/company_model.dart';

/// Thin wrapper around the Supabase queries used by the companies feature.
///
/// This is the only file within the companies feature that talks to
/// Supabase directly. Everything above this class deals with
/// [CompanyModel] / [BranchModel] and never sees Supabase types.
///
/// Tenant isolation is enforced by Row Level Security in the database:
/// * `select * from companies` only returns companies where the current
///   user has an active membership.
/// * `select * from branches where company_id = X` only returns branches
///   of companies the current user may access.
///
/// The data source therefore never accepts a `userId` and never trusts a
/// client-supplied identity. The active identity is always `auth.uid()`,
/// evaluated inside the database.
class CompanyRemoteDataSource {
  const CompanyRemoteDataSource(this._client);

  /// Active Supabase client, or `null` when Supabase was not initialised.
  final SupabaseClient? _client;

  /// Whether this data source can perform remote queries.
  bool get isAvailable => _client != null;

  /// Returns every active company the current user may access.
  ///
  /// The query is filtered and ordered server-side; RLS applies the tenant
  /// boundary transparently.
  Future<List<CompanyModel>> fetchMyCompanies() async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('companies')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return rows.map(CompanyModel.fromMap).toList(growable: false);
  }

  /// Returns every active branch of [companyId] the current user may access.
  ///
  /// When the current user has no membership in [companyId], RLS returns
  /// an empty list rather than raising an error. This is intentional: it
  /// avoids leaking the existence of companies the user cannot access.
  Future<List<BranchModel>> fetchCompanyBranches(String companyId) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('branches')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name', ascending: true);

    return rows.map(BranchModel.fromMap).toList(growable: false);
  }

  /// Returns the active Supabase client, or throws [CompanyException] when
  /// Supabase was not initialised.
  ///
  /// The return type is non-nullable on purpose: callers receive a client
  /// they can use directly, without `!` or redundant nullable checks.
  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const CompanyException(
        type: CompanyFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    return client;
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
}
