// lib/features/suppliers/domain/repositories/supplier_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/supplier.dart';

/// Categories of failures that the presentation layer can safely translate
/// into localized user messages.
///
/// Mirrors the Phase 1, Phase 3, Phase 4 and Phase 5 conventions so the
/// application has a single, consistent way of categorising safe failures.
/// Backend-specific error codes and raw messages never leave the data layer.
enum SupplierFailureType {
  /// The request could not reach the backend.
  network,

  /// The backend rejected the request as unauthorised (RLS or session).
  unauthorized,

  /// The requested supplier does not exist or is not accessible.
  notFound,

  /// A supplier with the same name already exists for this company.
  nameConflict,

  /// A supplier with the same code already exists for this company.
  codeConflict,

  /// A supplier with the same phone already exists for this company.
  phoneConflict,

  /// The supplier cannot be deleted because other rows still reference it.
  /// Reserved for Phase 7 (purchases) — currently unreachable but part of
  /// the enum so the presentation layer can present a specific message
  /// without a schema change later.
  inUse,

  /// The response could not be interpreted.
  invalidResponse,

  /// Any other unclassified failure.
  unknown,
}

/// Domain-level exception raised by [SupplierRepository] operations.
///
/// Carries a safe [SupplierFailureType] rather than a raw backend message so
/// the presentation layer can produce localized, user-friendly errors.
@immutable
class SupplierException extends Equatable implements Exception {
  const SupplierException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  /// Safe, categorized reason for the failure.
  final SupplierFailureType type;

  /// Original error, kept for logging. Never displayed to end users.
  final Object? cause;

  /// Original stack trace, kept for logging.
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'SupplierException(type: ${type.name})';
}

/// Contract for supplier operations.
///
/// All access decisions are ultimately enforced by Row Level Security in
/// the database: the data layer never accepts a `userId`, and `companyId`
/// is only ever used to filter results — RLS rejects any attempt to read
/// or write rows outside the caller's memberships.
abstract interface class SupplierRepository {
  /// Returns suppliers of [companyId] visible to the current user.
  ///
  /// When [includeInactive] is `false` (the default), inactive suppliers
  /// are omitted. Results are ordered by name.
  /// Throws [SupplierException] when the request fails.
  Future<List<Supplier>> listSuppliers(
    String companyId, {
    bool includeInactive = false,
  });

  /// Returns a single supplier by id.
  ///
  /// Throws [SupplierException] with type [SupplierFailureType.notFound]
  /// when the supplier does not exist or is not accessible to the current
  /// user.
  Future<Supplier> getSupplier(String supplierId);

  /// Creates a new supplier inside [companyId].
  ///
  /// Throws [SupplierException] with type
  /// [SupplierFailureType.nameConflict] / [codeConflict] / [phoneConflict]
  /// on uniqueness violations.
  /// Throws [SupplierException] with type [SupplierFailureType.unauthorized]
  /// when the caller lacks owner / admin / manager role.
  Future<Supplier> createSupplier({
    required String companyId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? address,
    String? notes,
  });

  /// Updates an existing supplier.
  ///
  /// Passing `null` for a nullable parameter leaves it unchanged, except for
  /// the five nullable fields that carry an explicit `clear*` flag:
  /// `code`, `phone`, `email`, `address`, `notes`. This resolves the
  /// ambiguity of `null` meaning both "leave as is" and "set to null".
  ///
  /// Throws [SupplierException] with the same typed conflicts as
  /// [createSupplier].
  Future<Supplier> updateSupplier({
    required String supplierId,
    String? name,
    String? code,
    bool clearCode = false,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? address,
    bool clearAddress = false,
    String? notes,
    bool clearNotes = false,
    bool? isActive,
  });

  /// Deletes a supplier.
  ///
  /// Throws [SupplierException] with type [SupplierFailureType.inUse] when
  /// other rows still reference the supplier (reserved for Phase 7). Callers
  /// should prefer [updateSupplier] with `isActive: false` for a soft
  /// disable.
  Future<void> deleteSupplier(String supplierId);
}
