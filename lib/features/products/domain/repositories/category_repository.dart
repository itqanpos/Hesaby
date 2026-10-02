// lib/features/products/domain/repositories/category_repository.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../entities/category.dart';

/// Categories of failures that the presentation layer can safely translate
/// into localized user messages.
///
/// Mirrors the Phase 1 and Phase 3 conventions so the application has a
/// single, consistent way of categorising safe failures. Backend-specific
/// error codes and raw messages never leave the data layer.
enum CategoryFailureType {
  /// The request could not reach the backend.
  network,

  /// The backend rejected the request as unauthorised (RLS or session).
  unauthorized,

  /// The requested category does not exist or is not accessible.
  notFound,

  /// A category with the same name already exists for this company.
  nameConflict,

  /// The category cannot be deleted because other rows still reference it.
  inUse,

  /// The response could not be interpreted.
  invalidResponse,

  /// Any other unclassified failure.
  unknown,
}

/// Domain-level exception raised by [CategoryRepository] operations.
///
/// Carries a safe [CategoryFailureType] rather than a raw backend message so
/// the presentation layer can produce localized, user-friendly errors.
@immutable
class CategoryException extends Equatable implements Exception {
  const CategoryException({
    required this.type,
    this.cause,
    this.stackTrace,
  });

  /// Safe, categorized reason for the failure.
  final CategoryFailureType type;

  /// Original error, kept for logging. Never displayed to end users.
  final Object? cause;

  /// Original stack trace, kept for logging.
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => <Object?>[type];

  @override
  String toString() => 'CategoryException(type: ${type.name})';
}

/// Contract for category operations.
///
/// All access decisions are ultimately enforced by Row Level Security in the
/// database: the data layer never accepts a `userId`, and `companyId` is
/// only ever used to filter results — RLS rejects any attempt to read or
/// write rows outside the caller's memberships.
abstract interface class CategoryRepository {
  /// Returns every category of [companyId] visible to the current user.
  ///
  /// The list is empty when the company has no categories or when the
  /// current user has no membership in the company (RLS filters rows).
  /// Throws [CategoryException] when the request fails.
  Future<List<Category>> listCategories(String companyId);

  /// Returns a single category by id.
  ///
  /// Throws [CategoryException] with type [CategoryFailureType.notFound] when
  /// the category does not exist or is not accessible to the current user.
  Future<Category> getCategory(String categoryId);

  /// Creates a new category inside [companyId].
  ///
  /// Throws [CategoryException] with type [CategoryFailureType.nameConflict]
  /// when a category with the same name already exists for the company.
  /// Throws [CategoryException] with type [CategoryFailureType.unauthorized]
  /// when the caller lacks owner / admin / manager role.
  Future<Category> createCategory({
    required String companyId,
    required String name,
    String? description,
    int sortOrder,
  });

  /// Updates an existing category.
  ///
  /// Passing `null` for a nullable parameter leaves it unchanged. [isActive]
  /// is the canonical way to soft-disable a category without deleting it.
  /// Throws [CategoryException] when the update fails.
  Future<Category> updateCategory({
    required String categoryId,
    String? name,
    String? description,
    int? sortOrder,
    bool? isActive,
  });

  /// Deletes a category.
  ///
  /// Throws [CategoryException] with type [CategoryFailureType.inUse] when
  /// products still reference this category. Callers should move or delete
  /// the referencing products first, or use [updateCategory] with
  /// `isActive: false` for a soft disable.
  Future<void> deleteCategory(String categoryId);
}
