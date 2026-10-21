// lib/features/companies/data/datasources/company_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/company_repository.dart';
import '../models/branch_model.dart';
import '../models/company_model.dart';

/// Thin wrapper around the Supabase queries used by the companies feature.
class CompanyRemoteDataSource {
  const CompanyRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  // ---------------------------------------------------------------------------
  // Companies
  // ---------------------------------------------------------------------------

  Future<List<CompanyModel>> fetchMyCompanies() async {
    final SupabaseClient client = _requireClient();

    // ⬇️ استخدام الدالة المخصصة (RPC) لتجاوز تعقيدات RLS
    final dynamic response = await client.rpc('get_my_companies');

    if (response == null) return const <CompanyModel>[];

    // ⬇️ إصلاح صارم للأنواع ليعمل على الأندرويد (Dart VM) والويب (dart2js)
    if (response is! List) {
      throw CompanyException(
        type: CompanyFailureType.invalidResponse,
        cause: 'get_my_companies returned ${response.runtimeType}, expected List.',
      );
    }

    final List<CompanyModel> result = <CompanyModel>[];
    for (final dynamic row in response) {
      if (row is Map<String, dynamic>) {
        result.add(CompanyModel.fromMap(row));
      } else if (row is Map) {
        result.add(CompanyModel.fromMap(Map<String, dynamic>.from(row)));
      } else {
        throw CompanyException(
          type: CompanyFailureType.invalidResponse,
          cause: 'get_my_companies row is ${row.runtimeType}, expected Map.',
        );
      }
    }
    return result;
  }

  Future<List<CompanyModel>> fetchAllCompanies() async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('companies')
        .select()
        .order('name', ascending: true);

    return rows.map(CompanyModel.fromMap).toList(growable: false);
  }

  Future<CompanyModel> updateCompany({
    required String companyId,
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
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'name': name,
      'currency': currency,
      'timezone': timezone,
      'legal_name': legalName,
      'phone': phone,
      'email': email,
      'address': address,
      'tax_number': taxNumber,
      'commercial_register': commercialRegister,
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
