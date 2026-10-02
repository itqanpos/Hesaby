// lib/features/products/data/datasources/category_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/category_repository.dart';
import '../models/category_model.dart';

/// Thin wrapper around the Supabase queries for the `categories` table.
///
/// This is the only file within the products feature that talks to Supabase
/// directly for categories. Everything above this class deals with
/// [CategoryModel] and never sees Supabase types.
///
/// Tenant isolation is enforced by Row Level Security:
/// * `select * from categories` only returns rows of companies where the
///   current user has an active membership.
/// * `insert / update / delete` only succeed on rows of companies where the
///   current user holds an owner / admin / manager role.
///
/// The data source therefore never accepts a `userId` and never trusts a
/// client-supplied identity. The active identity is always `auth.uid()`,
/// evaluated inside the database.
class CategoryRemoteDataSource {
  const CategoryRemoteDataSource(this._client);

  /// Active Supabase client, or `null` when Supabase was not initialised.
  final SupabaseClient? _client;

  /// Whether this data source can perform remote queries.
  bool get isAvailable => _client != null;

  /// Returns every active category of [companyId] visible to the current
  /// user, ordered by `sort_order` then `name`.
  Future<List<CategoryModel>> listCategories(String companyId) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await client
        .from('categories')
        .select()
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);

    return rows.map(CategoryModel.fromMap).toList(growable: false);
  }

  /// Returns the category with [categoryId], or throws if inaccessible.
  ///
  /// RLS filters the row out when the current user has no access, in which
  /// case PostgREST raises an error that the repository maps to
  /// [CategoryFailureType.notFound].
  Future<CategoryModel> getCategory(String categoryId) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> row = await client
        .from('categories')
        .select()
        .eq('id', categoryId)
        .single();

    return CategoryModel.fromMap(row);
  }

  /// Inserts a new category and returns the created row.
  Future<CategoryModel> createCategory({
    required String companyId,
    required String name,
    String? description,
    required int sortOrder,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      'company_id': companyId,
      'name': name.trim(),
      'sort_order': sortOrder,
      if (description != null) 'description': description.trim(),
    };

    final Map<String, dynamic> row = await client
        .from('categories')
        .insert(payload)
        .select()
        .single();

    return CategoryModel.fromMap(row);
  }

  /// Updates an existing category and returns the updated row.
  ///
  /// Only the fields that are non-null are sent; [clearDescription] forces
  /// the description column to `null` explicitly.
  Future<CategoryModel> updateCategory({
    required String categoryId,
    String? name,
    String? description,
    bool clearDescription = false,
    int? sortOrder,
    bool? isActive,
  }) async {
    final SupabaseClient client = _requireClient();

    final Map<String, dynamic> payload = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (clearDescription) 'description': null,
      if (!clearDescription && description != null)
        'description': description.trim(),
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isActive != null) 'is_active': isActive,
    };

    final Map<String, dynamic> row = await client
        .from('categories')
        .update(payload)
        .eq('id', categoryId)
        .select()
        .single();

    return CategoryModel.fromMap(row);
  }

  /// Deletes the category with [categoryId].
  Future<void> deleteCategory(String categoryId) async {
    final SupabaseClient client = _requireClient();

    await client.from('categories').delete().eq('id', categoryId);
  }

  /// Returns the active Supabase client, or throws when Supabase was not
  /// initialised.
  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const CategoryException(
        type: CategoryFailureType.unknown,
        cause: _supabaseUnavailableMessage,
      );
    }
    return client;
  }

  static const String _supabaseUnavailableMessage =
      'Supabase client is not initialised.';
}
