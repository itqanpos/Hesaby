// lib/features/products/presentation/providers/category_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../data/datasources/category_remote_datasource.dart';
import '../../data/repositories/category_repository_impl.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';

/// The application's category repository.
///
/// Builds a [CategoryRepositoryImpl] from the active Supabase client. When
/// Supabase is not initialised (for example when credentials were not
/// provided at build time), the underlying data source wraps a `null`
/// client and every operation fails predictably with a
/// [CategoryFailureType.unknown] exception instead of throwing a low-level
/// state error.
final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return CategoryRepositoryImpl(CategoryRemoteDataSource(client));
});

/// Provides the list of product categories for the currently selected
/// company.
///
/// The notifier reloads automatically whenever [companyContextProvider]
/// reports a different `currentCompany.id`. When no company is selected, it
/// resolves to an empty list, matching the presentation layer's expectation
/// that there is nothing to display until a company context exists.
class CategoriesNotifier extends AsyncNotifier<List<ProductCategory>> {
  @override
  Future<List<ProductCategory>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState state) => state.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return const <ProductCategory>[];
    }

    return ref.read(categoryRepositoryProvider).listCategories(companyId);
  }

  /// Creates a new category for the currently selected company.
  ///
  /// Throws [CategoryException] when there is no current company, or when
  /// the underlying repository rejects the operation.
  Future<ProductCategory> create({
    required String name,
    String? description,
    int sortOrder = 0,
  }) async {
    final String? companyId = _requireCurrentCompanyId();

    final ProductCategory created = await ref
        .read(categoryRepositoryProvider)
        .createCategory(
          companyId: companyId,
          name: name,
          description: description,
          sortOrder: sortOrder,
        );

    await _reload();
    return created;
  }

  /// Updates an existing category.
  ///
  /// Passing `null` for a nullable parameter leaves it unchanged, except for
  /// [description]: clearing it requires [clearDescription] to be `true`.
  Future<ProductCategory> update({
    required String categoryId,
    String? name,
    String? description,
    bool clearDescription = false,
    int? sortOrder,
    bool? isActive,
  }) async {
    final ProductCategory updated = await ref
        .read(categoryRepositoryProvider)
        .updateCategory(
          categoryId: categoryId,
          name: name,
          description: description,
          clearDescription: clearDescription,
          sortOrder: sortOrder,
          isActive: isActive,
        );

    await _reload();
    return updated;
  }

  /// Deletes a category.
  ///
  /// Throws [CategoryException] with type [CategoryFailureType.inUse] when
  /// products still reference the category.
  Future<void> delete(String categoryId) async {
    await ref.read(categoryRepositoryProvider).deleteCategory(categoryId);
    await _reload();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  String _requireCurrentCompanyId() {
    final CompanyContextState context = ref.read(companyContextProvider);
    final String? companyId = context.currentCompany?.id;
    if (companyId == null) {
      throw const CategoryException(
        type: CategoryFailureType.unauthorized,
        cause: 'No company is currently selected.',
      );
    }
    return companyId;
  }

  Future<void> _reload() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Provides the current company's product categories.
final AsyncNotifierProvider<CategoriesNotifier, List<ProductCategory>>
    categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<ProductCategory>>(
  CategoriesNotifier.new,
);
