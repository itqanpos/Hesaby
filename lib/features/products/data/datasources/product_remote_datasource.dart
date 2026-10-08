  // ---------------------------------------------------------------------------
  // Products — paginated / filtered / sorted
  // ---------------------------------------------------------------------------

  /// Fetches one page of products with optional filter, search and sort.
  ///
  /// - `categoryId` filters by category.
  /// - `isActive` filters by active flag; `null` means "both".
  /// - `searchQuery` matches name / SKU / barcode (case-insensitive
  ///   substring), with PostgREST special characters neutralised.
  /// - `sortField` and `sortAscending` control the ORDER BY clause.
  ///
  /// A tie-breaker on `id` is always appended so the pagination window
  /// stays stable across requests.
  Future<List<ProductModel>> listProductsPaged({
    required String companyId,
    required int offset,
    required int limit,
    String? categoryId,
    bool? isActive,
    String? searchQuery,
    required String sortColumn,
    required bool sortAscending,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client.from('products').select().eq('company_id', companyId);

    if (isActive != null) {
      query = query.eq('is_active', isActive);
    }
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }

    final String? rawSearch = searchQuery?.trim();
    if (rawSearch != null && rawSearch.isNotEmpty) {
      final String term = _sanitizeSearchTerm(rawSearch);
      if (term.isNotEmpty) {
        query = query.or(
          'name.ilike.%$term%,sku.ilike.%$term%,barcode.ilike.%$term%',
        );
      }
    }

    query = query.order(sortColumn, ascending: sortAscending);
    query = query.order('id', ascending: true);

    final List<Map<String, dynamic>> rows =
        await query.range(offset, offset + limit - 1);

    return rows.map(ProductModel.fromMap).toList(growable: false);
  }

  /// Counts products of [companyId], optionally filtered by active flag.
  ///
  /// Implemented by fetching only the `id` column and counting rows in
  /// Dart. This avoids a dependency on the PostgREST count header, which
  /// is not exposed uniformly by the Supabase Dart client across versions.
  /// The payload for 1,000–10,000 rows stays small (36–360 KB).
  Future<int> countProducts(
    String companyId, {
    bool? isActive,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client.from('products').select('id').eq('company_id', companyId);

    if (isActive != null) {
      query = query.eq('is_active', isActive);
    }

    final List<Map<String, dynamic>> rows = await query;

    return rows.length;
  }

  /// Neutralises PostgREST-special characters in a user-supplied search
  /// term before it is embedded in an `.or(...)` filter.
  ///
  /// PostgREST treats commas as filter separators and `%` / `_` as LIKE
  /// wildcards. Rather than attempt to escape them (the escaping rules
  /// differ between PostgREST versions), they are replaced with a single
  /// space and the result is trimmed. Users can still search for any
  /// ordinary word, number or hyphenated code.
  static String _sanitizeSearchTerm(String input) {
    final String cleaned =
        input.replaceAll(RegExp(r'[%,_\\]'), ' ').trim();
    return cleaned;
  }
