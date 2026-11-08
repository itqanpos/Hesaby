import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
class SalesRep extends Equatable {
  const SalesRep({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.fullName,
    this.email,
    required this.repType,
    required this.branchId,
    required this.branchName,
    this.phone,
    this.region,
    this.employeeCode,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String userId;
  final String fullName;
  final String? email;
  final String repType; // 'custody' | 'no_custody'
  final String branchId;
  final String branchName;
  final String? phone;
  final String? region;
  final String? employeeCode;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasCustody => repType == 'custody';
  String get repTypeLabel => hasCustody ? 'عهدة' : 'بدون عهدة';

  @override
  List<Object?> get props => [
        id, companyId, userId, fullName, email, repType,
        branchId, branchName, phone, region, employeeCode,
        isActive, createdAt, updatedAt,
      ];
}
