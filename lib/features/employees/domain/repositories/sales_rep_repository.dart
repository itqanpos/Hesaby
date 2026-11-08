import '../entities/sales_rep.dart';
import '../entities/sales_rep_candidate.dart';

abstract class SalesRepRepository {
  Future<List<SalesRep>> listReps(String companyId);
  Future<List<SalesRepCandidate>> listCandidates(String companyId);
  Future<String> upsertRep({
    required String companyId,
    required String userId,
    required String repType,
    required String branchId,
    String? phone,
    String? region,
    String? employeeCode,
    bool isActive = true,
  });
}

class SalesRepException implements Exception {
  const SalesRepException({required this.type, this.cause});
  final SalesRepFailureType type;
  final String? cause;
  @override
  String toString() =>
      'SalesRepException($type${cause != null ? ': $cause' : ''})';
}

enum SalesRepFailureType {
  network,
  unauthorized,
  permissionDenied,
  validationFailed,
  notFound,
  invalidResponse,
  unknown,
}
