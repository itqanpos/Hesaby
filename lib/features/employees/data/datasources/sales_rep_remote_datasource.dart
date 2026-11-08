import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/sales_rep.dart';
import '../../domain/entities/sales_rep_candidate.dart';
import '../../domain/repositories/sales_rep_repository.dart';

class SalesRepRemoteDataSource {
  SalesRepRemoteDataSource(this._client);
  final SupabaseClient? _client;

  SupabaseClient get _db {
    final c = _client;
    if (c == null) {
      throw const SalesRepException(
        type: SalesRepFailureType.network,
        cause: 'Supabase not initialized',
      );
    }
    return c;
  }

  Future<List<SalesRep>> listReps(String companyId) async {
    try {
      // 1) أسماء الأعضاء (مصدر full_name)
      final candidatesRaw = await _db.rpc(
        'admin_list_rep_candidates',
        params: {'p_company_id': companyId},
      );
      final Map<String, Map<String, dynamic>> membersByUserId = {};
      for (final c in (candidatesRaw as List)) {
        final m = c as Map<String, dynamic>;
        membersByUserId[m['user_id'] as String] = m;
      }

      // 2) تفاصيل المندوبين + اسم الفرع
      final repsRaw = await _db
          .from('sales_reps')
          .select(
            'id, company_id, user_id, rep_type, branch_id, phone, region, '
            'employee_code, is_active, created_at, updated_at, '
            'branches!inner(name)',
          )
          .eq('company_id', companyId)
          .order('created_at', ascending: false);

      return (repsRaw as List).map((r) {
        final m = r as Map<String, dynamic>;
        final userId = m['user_id'] as String;
        final member = membersByUserId[userId];
        final branch = m['branches'] as Map?;
        return SalesRep(
          id: m['id'] as String,
          companyId: m['company_id'] as String,
          userId: userId,
          fullName: (member?['full_name'] as String?) ?? 'بدون اسم',
          email: member?['email'] as String?,
          repType: (m['rep_type'] as String?) ?? 'no_custody',
          branchId: m['branch_id'] as String,
          branchName: (branch?['name'] as String?) ?? '—',
          phone: m['phone'] as String?,
          region: m['region'] as String?,
          employeeCode: m['employee_code'] as String?,
          isActive: (m['is_active'] as bool?) ?? true,
          createdAt: DateTime.parse(m['created_at'] as String),
          updatedAt: DateTime.parse(m['updated_at'] as String),
        );
      }).toList();
    } on SalesRepException {
      rethrow;
    } on PostgrestException catch (e) {
      throw _mapPgError(e);
    } on Object catch (e) {
      throw SalesRepException(
        type: SalesRepFailureType.unknown,
        cause: e.toString(),
      );
    }
  }

  Future<List<SalesRepCandidate>> listCandidates(String companyId) async {
    try {
      final res = await _db.rpc(
        'admin_list_rep_candidates',
        params: {'p_company_id': companyId},
      );
      return (res as List).map((c) {
        final m = c as Map<String, dynamic>;
        return SalesRepCandidate(
          userId: m['user_id'] as String,
          fullName: (m['full_name'] as String?) ?? 'بدون اسم',
          email: m['email'] as String?,
          role: (m['role'] as String?) ?? '',
          isAlreadyRep: (m['is_already_rep'] as bool?) ?? false,
          salesRepId: m['sales_rep_id'] as String?,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw _mapPgError(e);
    } on Object catch (e) {
      throw SalesRepException(
        type: SalesRepFailureType.unknown,
        cause: e.toString(),
      );
    }
  }

  Future<String> upsertRep({
    required String companyId,
    required String userId,
    required String repType,
    required String branchId,
    String? phone,
    String? region,
    String? employeeCode,
    bool isActive = true,
  }) async {
    try {
      final res = await _db.rpc('admin_upsert_sales_rep', params: {
        'p_company_id': companyId,
        'p_user_id': userId,
        'p_rep_type': repType,
        'p_branch_id': branchId,
        'p_warehouse_id': null,
        'p_treasury_id': null,
        'p_employee_code': employeeCode,
        'p_phone': phone,
        'p_region': region,
        'p_is_active': isActive,
      });
      return res as String;
    } on PostgrestException catch (e) {
      throw _mapPgError(e);
    } on Object catch (e) {
      throw SalesRepException(
        type: SalesRepFailureType.unknown,
        cause: e.toString(),
      );
    }
  }

  SalesRepException _mapPgError(PostgrestException e) {
    final msg = '${e.message} ${e.details ?? ''} ${e.code ?? ''}';
    if (msg.contains('PERMISSION_DENIED') || e.code == '42501') {
      return const SalesRepException(
        type: SalesRepFailureType.permissionDenied,
      );
    }
    if (msg.contains('VALIDATION_FAILED') || e.code == '22023') {
      return SalesRepException(
        type: SalesRepFailureType.validationFailed,
        cause: e.message,
      );
    }
    return SalesRepException(
      type: SalesRepFailureType.unknown,
      cause: e.message,
    );
  }
}
