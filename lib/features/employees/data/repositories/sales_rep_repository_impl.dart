import '../../domain/entities/sales_rep.dart';
import '../../domain/entities/sales_rep_candidate.dart';
import '../../domain/repositories/sales_rep_repository.dart';
import '../datasources/sales_rep_remote_datasource.dart';

class SalesRepRepositoryImpl implements SalesRepRepository {
  SalesRepRepositoryImpl(this._remote);
  final SalesRepRemoteDataSource _remote;

  @override
  Future<List<SalesRep>> listReps(String companyId) =>
      _remote.listReps(companyId);

  @override
  Future<List<SalesRepCandidate>> listCandidates(String companyId) =>
      _remote.listCandidates(companyId);

  @override
  Future<String> upsertRep({
    required String companyId,
    required String userId,
    required String repType,
    required String branchId,
    String? phone,
    String? region,
    String? employeeCode,
    bool isActive = true,
  }) =>
      _remote.upsertRep(
        companyId: companyId,
        userId: userId,
        repType: repType,
        branchId: branchId,
        phone: phone,
        region: region,
        employeeCode: employeeCode,
        isActive: isActive,
      );
}
