import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/sales_rep_remote_datasource.dart';
import '../../data/repositories/sales_rep_repository_impl.dart';
import '../../domain/entities/sales_rep.dart';
import '../../domain/entities/sales_rep_candidate.dart';
import '../../domain/repositories/sales_rep_repository.dart';

final Provider<SalesRepRepository> salesRepRepositoryProvider =
    Provider<SalesRepRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return SalesRepRepositoryImpl(SalesRepRemoteDataSource(client));
});

class SalesRepsNotifier extends AsyncNotifier<List<SalesRep>> {
  @override
  Future<List<SalesRep>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) return const <SalesRep>[];
    return ref.read(salesRepRepositoryProvider).listReps(companyId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<String> upsert({
    required String userId,
    required String repType,
    required String branchId,
    String? phone,
    String? region,
    String? employeeCode,
    bool isActive = true,
  }) async {
    final String companyId = _requireCompanyId();
    final String id = await ref.read(salesRepRepositoryProvider).upsertRep(
          companyId: companyId,
          userId: userId,
          repType: repType,
          branchId: branchId,
          phone: phone,
          region: region,
          employeeCode: employeeCode,
          isActive: isActive,
        );
    await refresh();
    // نُحدّث قائمة المرشحين أيضًا (is_already_rep يتغير)
    ref.invalidate(repCandidatesProvider);
    return id;
  }

  Future<void> toggleActive(SalesRep rep) async {
    final String companyId = _requireCompanyId();
    await ref.read(salesRepRepositoryProvider).upsertRep(
          companyId: companyId,
          userId: rep.userId,
          repType: rep.repType,
          branchId: rep.branchId,
          phone: rep.phone,
          region: rep.region,
          employeeCode: rep.employeeCode,
          isActive: !rep.isActive,
        );
    await refresh();
  }

  String _requireCompanyId() {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? id = ctx.currentCompany?.id;
    if (id == null) {
      throw const SalesRepException(
        type: SalesRepFailureType.unauthorized,
        cause: 'No company selected.',
      );
    }
    return id;
  }
}

final AsyncNotifierProvider<SalesRepsNotifier, List<SalesRep>>
    salesRepsProvider =
    AsyncNotifierProvider<SalesRepsNotifier, List<SalesRep>>(
  SalesRepsNotifier.new,
);

class RepCandidatesNotifier extends AsyncNotifier<List<SalesRepCandidate>> {
  @override
  Future<List<SalesRepCandidate>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) return const <SalesRepCandidate>[];
    return ref.read(salesRepRepositoryProvider).listCandidates(companyId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final AsyncNotifierProvider<RepCandidatesNotifier, List<SalesRepCandidate>>
    repCandidatesProvider =
    AsyncNotifierProvider<RepCandidatesNotifier, List<SalesRepCandidate>>(
  RepCandidatesNotifier.new,
);

/// قائمة الفروع النشطة — تُستخدم في dropdown النموذج فقط.
final FutureProvider<List<Map<String, dynamic>>> branchesForRepsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final CompanyContextState ctx = ref.watch(companyContextProvider);
  final String? companyId = ctx.currentCompany?.id;
  if (companyId == null) return const <Map<String, dynamic>>[];
  try {
    final res = await Supabase.instance.client
        .from('branches')
        .select('id, name')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name');
    return (res as List).cast<Map<String, dynamic>>();
  } on Object {
    return const <Map<String, dynamic>>[];
  }
});
