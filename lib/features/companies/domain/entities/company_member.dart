// lib/features/companies/domain/entities/company_member.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Foundational role identifiers used by `company_members.role`.
///
/// The role still drives the coarse Row Level Security policies on the
/// backend (`owner`/`admin`/`manager` can edit, others cannot). The
/// fine-grained permissions live on [CompanyMember.deniedPermissions].
abstract final class MemberRole {
  static const String owner = 'owner';
  static const String admin = 'admin';
  static const String manager = 'manager';
  static const String cashier = 'cashier';
  static const String inventoryClerk = 'inventory_clerk';

  static const List<String> all = <String>[
    owner,
    admin,
    manager,
    cashier,
    inventoryClerk,
  ];

  /// Arabic label for a role code. Falls back to the code when unknown.
  static String label(String role) {
    switch (role) {
      case owner:
        return 'المالك';
      case admin:
        return 'مدير عام';
      case manager:
        return 'مدير';
      case cashier:
        return 'كاشير';
      case inventoryClerk:
        return 'أمين مخزن';
      default:
        return role;
    }
  }
}

/// A single member of a company.
///
/// The entity merges a row from `company_members` with the member's
/// `profiles` row (name, phone) so the UI can render a readable list
/// without a second lookup.
@immutable
class CompanyMember extends Equatable {
  const CompanyMember({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.role,
    required this.isActive,
    required this.deniedPermissions,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.email,
    this.phone,
  });

  final String id;
  final String companyId;
  final String userId;
  final String role;
  final bool isActive;

  /// Set of permission codes explicitly revoked. Empty = all granted.
  final List<String> deniedPermissions;

  /// Optional display name read from `profiles.full_name`.
  final String? displayName;

  /// Optional email address read from the auth session (never from
  /// `profiles`, which does not store emails).
  final String? email;

  /// Optional phone read from `profiles.phone`.
  final String? phone;

  final DateTime createdAt;
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Role helpers
  // ---------------------------------------------------------------------------

  bool get isOwner => role == MemberRole.owner;
  bool get isAdmin => role == MemberRole.admin;
  bool get isManager => role == MemberRole.manager;
  bool get isCashier => role == MemberRole.cashier;
  bool get isInventoryClerk => role == MemberRole.inventoryClerk;

  /// Whether this member can manage other members (owner/admin/manager).
  bool get canManageMembers => isOwner || isAdmin || isManager;

  /// Whether the role itself is locked (i.e. cannot be demoted by a
  /// non-owner). Owners are protected by a DB trigger.
  bool get isProtectedRole => isOwner;

  // ---------------------------------------------------------------------------
  // Permission helpers
  // ---------------------------------------------------------------------------

  /// Whether [code] is granted to this member. The rule is:
  ///
  /// ```
  /// active  AND  code NOT IN deniedPermissions
  /// ```
  ///
  /// Inactive members always have zero permissions.
  bool hasPermission(String code) =>
      isActive && !deniedPermissions.contains(code);

  /// Whether [code] was explicitly revoked. Useful for the UI to render
  /// the toggle state.
  bool isDenied(String code) => deniedPermissions.contains(code);

  /// Number of revoked permissions. Zero means "full access".
  int get deniedCount => deniedPermissions.length;

  // ---------------------------------------------------------------------------
  // Copy helpers (used by optimistic updates)
  // ---------------------------------------------------------------------------

  CompanyMember copyWith({
    String? role,
    bool? isActive,
    List<String>? deniedPermissions,
    DateTime? updatedAt,
  }) {
    return CompanyMember(
      id: id,
      companyId: companyId,
      userId: userId,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      deniedPermissions: deniedPermissions ?? this.deniedPermissions,
      displayName: displayName,
      email: email,
      phone: phone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        companyId,
        userId,
        role,
        isActive,
        deniedPermissions,
        displayName,
        email,
        phone,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'CompanyMember(id: $id, userId: $userId, role: $role, '
      'isActive: $isActive, denied: ${deniedPermissions.length})';
}
