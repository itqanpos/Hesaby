// lib/features/companies/domain/repositories/company_members_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/company_member.dart';

/// Categories of failures raised by [CompanyMembersRepository] operations.
enum MemberFailureType {
  network,
  unauthorized,
  notFound,
  cannotModifyOwner,
  lastOwnerProtection,
  invalidRole,
  invalidResponse,
  unknown,
}

/// Domain-level exception raised by [CompanyMembersRepository] operations.
@immutable
class MemberException extends Equatable implements Exception {
  const MemberException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  final MemberFailureType type;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'MemberException(type: ${type.name})';
}

/// Contract for reading and updating the members of a company.
///
/// All access decisions are enforced by Row Level Security: listing is
/// restricted to owner/admin/manager, and updates are restricted to the
/// same set of roles (see the `202610170001_member_permissions.sql`
/// migration).
abstract interface class CompanyMembersRepository {
  /// Lists every member of [companyId], including inactive ones.
  ///
  /// Only accessible when the caller is an owner, admin, or manager of
  /// the company. Throws [MemberException] on failure.
  Future<List<CompanyMember>> listMembers(String companyId);

  /// Returns the membership row of [userId] in [companyId], or `null`
  /// when the user is not a member.
  ///
  /// This works for any authenticated member (the RLS policy always
  /// allows reading one's own row), and is used to compute the current
  /// user's own permissions.
  Future<CompanyMember?> getMemberByUser({
    required String companyId,
    required String userId,
  });

  /// Updates the role, active flag, and/or denied permissions of a member.
  ///
  /// All parameters are optional; a `null` value leaves the corresponding
  /// field unchanged. When [deniedPermissions] is provided, it **replaces**
  /// the current deny-list entirely (not a merge).
  ///
  /// Throws [MemberException] when the request fails — in particular with
  /// [MemberFailureType.cannotModifyOwner] when the target is an owner and
  /// [MemberFailureType.lastOwnerProtection] when the change would leave
  /// the company without an active owner.
  Future<CompanyMember> updateMember({
    required String memberId,
    String? role,
    bool? isActive,
    List<String>? deniedPermissions,
  });
}
