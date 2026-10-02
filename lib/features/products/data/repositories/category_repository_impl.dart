// lib/features/products/data/repositories/category_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../datasources/category_remote_datasource.dart';
import '../models/category_model.dart';

/// Concrete implementation of [CategoryRepository] backed by Supabase.
///
/// Responsibilities:
/// * Call the remote data source.
/// * Translate [CategoryModel] rows into pure [ProductCategory] entities.
/// * Translate Supabase / PostgREST errors into safe [CategoryException]s
///   carrying a [CategoryFailureType]. Raw backend messages never leave
///   this layer, and no credential or token is ever logged.
class CategoryRepositoryImpl implements CategoryRepository {
  const CategoryRepositoryImpl(this._remoteDataSource);

  final CategoryRemoteDataSource _remoteDataSource;

  @override
  Future<List<ProductCategory>> listCategories(String companyId) async {
    try {
      final List<CategoryModel> models =
          await _remoteDataSource.listCategories(companyId);
      return models
          .map((CategoryModel model) => model.toEntity())
          .toList(growable: false);
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'listCategories');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'listCategories');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'listCategories');
    } on CategoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'listCategories');
    }
  }

  @override
  Future<ProductCategory> getCategory(String categoryId) async {
    try {
      final CategoryModel model =
          await _remoteDataSource.getCategory(categoryId);
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'getCategory');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getCategory');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getCategory');
    } on CategoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getCategory');
    }
  }

  @override
  Future<ProductCategory> createCategory({
    required String companyId,
    required String name,
    String? description,
    int sortOrder = 0,
  }) async {
    try {
      final CategoryModel model = await _remoteDataSource.createCategory(
        companyId: companyId,
        name: name,
        description: description,
        sortOrder: sortOrder,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'createCategory');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'createCategory');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'createCategory');
    } on CategoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'createCategory');
    }
  }

  @override
  Future<ProductCategory> updateCategory({
    required String categoryId,
    String? name,
    String? description,
    bool clearDescription = false,
    int? sortOrder,
    bool? isActive,
  }) async {
    try {
      final CategoryModel model = await _remoteDataSource.updateCategory(
        categoryId: categoryId,
        name: name,
        description: description,
        clearDescription: clearDescription,
        sortOrder: sortOrder,
        isActive: isActive,
      );
      return model.toEntity();
    } on FormatException catch (error, stackTrace) {
      throw _mapInvalidResponse(error, stackTrace, operation: 'updateCategory');
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'updateCategory');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'updateCategory');
    } on CategoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'updateCategory');
    }
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    try {
      await _remoteDataSource.deleteCategory(categoryId);
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'deleteCategory');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'deleteCategory');
    } on CategoryException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'deleteCategory');
    }
  }

  // ---------------------------------------------------------------------------
  // Error mapping
  // ---------------------------------------------------------------------------

  static CategoryException _mapInvalidResponse(
    FormatException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.error(
      'Invalid response during "$operation" (FormatException).',
      error,
      stackTrace,
    );
    return CategoryException(
      type: CategoryFailureType.invalidResponse,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static CategoryException _mapPostgrest(
    supabase.PostgrestException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final CategoryFailureType type = _classifyPostgrest(error);

    AppLogger.warning(
      'PostgREST error during "$operation" mapped to ${type.name} '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return CategoryException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static CategoryException _mapAuth(
    supabase.AuthException error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    AppLogger.warning(
      'Auth error during "$operation" mapped to unauthorized '
      '(code: ${error.code ?? 'n/a'}).',
    );

    return CategoryException(
      type: CategoryFailureType.unauthorized,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static CategoryException _mapUnknown(
    Object error,
    StackTrace stackTrace, {
    required String operation,
  }) {
    final CategoryFailureType type = _looksLikeNetworkFailure(error)
        ? CategoryFailureType.network
        : CategoryFailureType.unknown;

    AppLogger.error(
      'Unhandled error during "$operation" '
      '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
      error,
      stackTrace,
    );

    return CategoryException(
      type: type,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Classifies a PostgREST error into a safe [CategoryFailureType].
  ///
  /// Codes handled explicitly:
  /// * `23505` unique_violation  → nameConflict
  /// * `23503` foreign_key_violation → inUse
  /// * `PGRST116` no rows / multiple rows for single() → notFound
  /// * `42501` insufficient_privilege → unauthorized
  /// * `28xxx` invalid_authorization_specification → unauthorized
  /// * `42xxx` syntax / undefined table → invalidResponse
  static CategoryFailureType _classifyPostgrest(
    supabase.PostgrestException error,
  ) {
    final String code = (error.code ?? '').toUpperCase();
    final String message = error.message.toLowerCase();

    if (code == '23505') {
      return CategoryFailureType.nameConflict;
    }
    if (code == '23503') {
      return CategoryFailureType.inUse;
    }
    if (code == 'PGRST116') {
      return CategoryFailureType.notFound;
    }
    if (code.startsWith('42501') || code.startsWith('28')) {
      return CategoryFailureType.unauthorized;
    }
    if (code.startsWith('42')) {
      return CategoryFailureType.invalidResponse;
    }

    if (message.contains('permission denied') ||
        message.contains('row level security') ||
        message.contains('jwt')) {
      return CategoryFailureType.unauthorized;
    }

    if (message.contains('duplicate key') ||
        message.contains('unique constraint')) {
      return CategoryFailureType.nameConflict;
    }

    if (message.contains('foreign key') ||
        message.contains('violates foreign key')) {
      return CategoryFailureType.inUse;
    }

    if (_messageLooksLikeNetwork(message)) {
      return CategoryFailureType.network;
    }

    return CategoryFailureType.unknown;
  }

  static bool _looksLikeNetworkFailure(Object error) {
    final String description = error.toString().toLowerCase();
    return _messageLooksLikeNetwork(description);
  }

  static bool _messageLooksLikeNetwork(String value) {
    return value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection') ||
        value.contains('timeout') ||
        value.contains('timed out') ||
        value.contains('unreachable') ||
        value.contains('failed host lookup') ||
        value.contains('clientexception');
  }
}
