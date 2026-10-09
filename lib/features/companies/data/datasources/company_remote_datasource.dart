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
///   user has an active membership (or every company, if the caller is a
///   platform admin).
/// * `insert / update / delete` on `companies` and `branches` only succeed
///   when the current user holds the `owner` or `admin` role in the target
///   company — or is a platform admin.
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

  // ---------------------------------------------------------------------------
  // Companies
  // ---------------------------------------------------------------------------

  /// Returns every active company the current user may access.
  ///
  /// The query is filtered and ordered server-side; RLS applies the tenant
  /// boundary transparently. For a platform admin, RLS returns every active
  /// company in the platform.
  Future<List<CompanyModel>> fetchMyCompanies() async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('companies')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);

    return rows.map(CompanyModel.fromMap).toList(growable: false);
  }

  /// Phase T-2: returns every company in the platform (active and inactive).
  ///
  /// Relies exclusively on the `companies_platform_admin_select_all` RLS
  /// policy. A non-admin caller receives an empty list (RLS silently filters
  /// every row), which the repository surfaces as an empty result — never
  /// as an error. This mirrors the "no companies" behaviour of
  /// [fetchMyCompanies].
  Future<List<CompanyModel>> fetchAllCompanies() async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('companies')
        .select()
        .order('name', ascending: true);

    return rows.map(CompanyModel.fromMap).toList(growable: false);
  }

  /// Updates the profile of [companyId] and returns the updated row.
  ///
  /// Uses `maybeSingle()` so that an RLS-blocked update — which affects
  /// zero rows and then returns an empty result — is surfaced as
  /// [CompanyFailureType.unauthorized] instead of a raw PostgREST error.
  /// The company id is always supplied by the authenticated context, so a
  /// zero-row result can only mean the role check failed.
  Future<CompanyModel> updateCompany({
    required String companyId,
    required String name,
    required String currency,
    required String timezone,
    String? legalName,
    String? phone,
    String? email,
    String? address,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'name': name,
      'currency': currency,
      'timezone': timezone,
      'legal_name': legalName,
      'phone': phone,
      'email': email,
      'address': address,
    };

    final Map<String, dynamic>? row = await client
        .from('companies')
        .update(payload)
        .eq('id', companyId)
        .select()
        .maybeSingle();

    if (row == null) {
      throw const CompanyException(
        type: CompanyFailureType.unauthorized,
        cause: 'Update affected no rows (RLS role check likely failed).',
      );
    }

    return CompanyModel.fromMap(row);
  }

  /// Phase T-2: updates only the subscription fields of [companyId].
  ///
  /// Same `maybeSingle` reasoning as [updateCompany]: a zero-row result
  /// means RLS refused the write (caller is not a platform admin).
  Future<CompanyModel> updateCompanySubscription({
    required String companyId,
    required String subscriptionStatus,
    String? planId,
    String? billingCycle,
    DateTime? subscribedUntil,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'subscription_status': subscriptionStatus,
      'plan_id': planId,
      'billing_cycle': billingCycle,
      'subscribed_until': subscribedUntil?.toUtc().toIso8601String(),
    };

    final Map<String, dynamic>? row = await client
        .from('companies')
        .update(payload)
        .eq('id', companyId)
        .select()
        .maybeSingle();

    if (row == null) {
      throw const CompanyException(
        type: CompanyFailureType.unauthorized,
        cause: 'Subscription update affected no rows '
            '(RLS: caller is not a platform admin).',
      );
    }

    return CompanyModel.fromMap(row);
  }

  /// Phase T-3: creates a company owned by the current user via RPC.
  ///
  /// The RPC `create_my_company` is the only writable entry point into
  /// `companies` for a regular authenticated user — the client never
  /// inserts directly. It returns the new company id; the row is then
  /// re-fetched so the caller receives a fully populated [CompanyModel]
  /// (with all subscription columns defaulted by the database).
  Future<CompanyModel> createMyCompany({required String name}) async {
    final SupabaseClient client = _requireClient();

    final dynamic rpcResult = await client.rpc(
      'create_my_company',
      params: <String, dynamic>{'p_name': name},
    );

    final String companyId;
    if (rpcResult is String) {
      companyId = rpcResult;
    } else if (rpcResult != null) {
      companyId = rpcResult.toString();
    } else {
      throw const CompanyException(
        type: CompanyFailureType.invalidResponse,
        cause: 'create_my_company returned no id.',
      );
    }

    final Map<String, dynamic> row = await client
        .from('companies')
        .select()
        .eq('id', companyId)
        .single();

    return CompanyModel.fromMap(row);
  }

  // ---------------------------------------------------------------------------
  // Branches — reads
  // ---------------------------------------------------------------------------

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

  /// Returns every branch (active and inactive) of [companyId].
  ///
  /// Active branches are listed first so that management UIs naturally
  /// surface actionable rows before deactivated ones.
  Future<List<BranchModel>> fetchAllCompanyBranches(String companyId) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('branches')
        .select()
        .eq('company_id', companyId)
        .order('is_active', ascending: false)
        .order('name', ascending: true);

    return rows.map(BranchModel.fromMap).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Branches — mutations
  // ---------------------------------------------------------------------------

  /// Inserts a new branch and returns the created row.
  Future<BranchModel> insertBranch({
    required String companyId,
    required String name,
    String? code,
    String? address,
    String? phone,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': companyId,
      'name': name,
      'code': code,
      'address': address,
      'phone': phone,
    };

    final Map<String, dynamic> row = await client
        .from('branches')
        .insert(payload)
        .select()
        .single();

    return BranchModel.fromMap(row);
  }

  /// Updates an existing branch and returns the updated row.
  Future<BranchModel> updateBranch({
    required String branchId,
    required String name,
    String? code,
    String? address,
    String? phone,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'name': name,
      'code': code,
      'address': address,
      'phone': phone,
    };

    final Map<String, dynamic>? row = await client
        .from('branches')
        .update(payload)
        .eq('id', branchId)
        .select()
        .maybeSingle();

    if (row == null) {
      throw const CompanyException(
        type: CompanyFailureType.unauthorized,
        cause: 'Update affected no rows (RLS role check likely failed).',
      );
    }

    return BranchModel.fromMap(row);
  }

  /// Toggles `is_active` on a branch and returns the updated row.
  Future<BranchModel> updateBranchActive({
    required String branchId,
    required bool isActive,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic>? row = await client
        .from('branches')
        .update(<String, dynamic>{'is_active': isActive})
        .eq('id', branchId)
        .select()
        .maybeSingle();

    if (row == null) {
      throw const CompanyException(
        type: CompanyFailureType.unauthorized,
        cause: 'Update affected no rows (RLS role check likely failed).',
      );
    }

    return BranchModel.fromMap(row);
  }

  // ---------------------------------------------------------------------------
  // Client
  // ---------------------------------------------------------------------------

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
