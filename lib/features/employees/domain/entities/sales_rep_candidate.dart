import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
class SalesRepCandidate extends Equatable {
  const SalesRepCandidate({
    required this.userId,
    required this.fullName,
    this.email,
    required this.role,
    required this.isAlreadyRep,
    this.salesRepId,
  });

  final String userId;
  final String fullName;
  final String? email;
  final String role;
  final bool isAlreadyRep;
  final String? salesRepId;

  @override
  List<Object?> get props =>
      [userId, fullName, email, role, isAlreadyRep, salesRepId];
}
