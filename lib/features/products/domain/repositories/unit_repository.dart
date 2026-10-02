// lib/features/products/domain/repositories/unit_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/unit.dart';

/// Categories of failures that the presentation layer can safely translate
/// into localized user messages.
///
/// Mirrors the Phase 1 and Phase 3 conventions so the application has a
/// single, consistent way of categorising safe failures. Backend-specific
/// error codes and raw messages never leave the data layer.
enum UnitFailureType {
  /// The request could not reach the backend.
  network,

  /// The backend rejected the request as unauthorised (RLS or session).
  unauthorized,

  /// The requested unit does not exist or is not accessible.
  notFound,

  /// A unit with the same name already exists for this company.
  nameConflict,

  /// A unit with the same symbol already exists for this company.
  symbolConflict,

  /// The unit cannot be deleted because other rows still reference it.
  inUse,

  /// The response could not be interpreted.
  invalidResponse,

  /// Any other unclassified failure.
  unknown,
}

/// Domain-level exception raised by [UnitRepository] operations.
///
/// Carries a safe [UnitFailureType] rather than a raw backend message so
/// the presentation layer can produce localized, user-friendly errors.
@immutable
class UnitException extends Equatable implements Exception {
  const UnitException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  /// Safe, categorized reason for the failure.
  final UnitFailureType type;

  /// Original error, kept for logging. Never displayed to end users.
  final Object? cause;

  /// Original stack trace, kept for logging.
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'UnitException(type: ${type.name})';
}

/// Contract for unit operations.
///
/// All access decisions are ultimately enforced by Row Level Security in the
/// database: the data layer never accepts a `userId`, and `companyId` is
/// only ever used to filter results — RLS rejects any attempt to read or
/// write rows outside the caller's memberships.
abstract interface class UnitRepository {
  /// Returns every unit of [companyId] visible to the current user.
  ///
  /// The list is empty when the company has no units or when the current
  /// user has no membership in the company (RLS filters rows).
  /// Throws [UnitException] when the request fails.
  Future<List<Unit>> listUnits(String companyId);

  /// Returns a single unit by id.
  ///
  /// Throws [UnitException] with type [UnitFailureType.notFound] when the
  /// unit does not exist or is not accessible to the current user.
  Future<Unit> getUnit(String unitId);

  /// Creates a new unit inside [companyId].
  ///
  /// Throws [UnitException] with type [UnitFailureType.nameConflict] when a
  /// unit with the same name already exists, or
  /// [UnitFailureType.symbolConflict] when a unit with the same symbol
  /// already exists for the company.
  /// Throws [UnitException] with type [UnitFailureType.unauthorized] when
  /// the caller lacks owner / admin / manager role.
  Future<Unit> createUnit({
    required String companyId,
    required String name,
    String? symbol,
  });

  /// Updates an existing unit.
  ///
  /// Passing `null` for a nullable parameter leaves it unchanged, except for
  /// [symbol]: because [symbol] is itself nullable, clearing it requires
  /// [clearSymbol] to be `true`. This avoids the ambiguity of `null` meaning
  /// both "leave as is" and "set to null".
  Future<Unit> updateUnit({
    required String unitId,
    String? name,
    String? symbol,
    bool clearSymbol = false,
    bool? isActive,
  });

  /// Deletes a unit.
  ///
  /// Throws [UnitException] with type [UnitFailureType.inUse] when products
  /// or product_unit conversions still reference this unit. Callers should
  /// reassign those references first, or use [updateUnit] with
  /// `isActive: false` for a soft disable.
  Future<void> deleteUnit(String unitId);
}
