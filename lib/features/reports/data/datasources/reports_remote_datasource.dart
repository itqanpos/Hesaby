// lib/features/reports/data/datasources/reports_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/reports_repository.dart';

/// Thin wrapper over the Supabase queries the reports feature needs.
///
/// The heavy lifting (aggregation, grouping) happens client-side in
/// `ReportsRepositoryImpl`; this datasource only fetches narrow slices of
/// the underlying tables with the correct filters.
class ReportsRemoteDataSource {
  const ReportsRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  /// Safety cap for report queries. Reports over longer periods fetch this
  /// many rows at most.
  static const int safetyLimit = 5000;

  /// How many ids to pass to a single `IN (...)` filter. PostgREST has a
  /// URL length limit, so larger sets are chunked.
  static const int inFilterChunkSize = 150;

  // ===========================================================================
  // SALES
  // ===========================================================================

  /// Fetches the fields of every sale in the company over the period.
  Future<List<Map<String, dynamic>>> fetchSales({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
    int? limit,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('sales')
        .select(
          'id, status, total, paid_amount, discount, tax_amount, '
          'customer_id, created_by, sale_date',
        )
        .eq('company_id', companyId);

    if (fromDate != null) {
      query = query.gte('sale_date', _formatTimestamp(fromDate));
    }
    if (toDate != null) {
      query = query.lte('sale_date', _formatTimestamp(toDate));
    }

    final int effectiveLimit =
        (limit == null || limit <= 0) ? safetyLimit : limit;

    final List<Map<String, dynamic>> rows = await query.limit(effectiveLimit);
    return rows;
  }

  /// Returns the ids of every confirmed sale in the period.
  Future<List<String>> fetchConfirmedSaleIds({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('sales')
        .select('id')
        .eq('company_id', companyId)
        .eq('status', 'confirmed');

    if (fromDate != null) {
      query = query.gte('sale_date', _formatTimestamp(fromDate));
    }
    if (toDate != null) {
      query = query.lte('sale_date', _formatTimestamp(toDate));
    }

    final List<Map<String, dynamic>> rows = await query.limit(safetyLimit);

    return rows
        .map((Map<String, dynamic> r) => r['id'])
        .whereType<String>()
        .toList(growable: false);
  }

  /// Fetches the `sale_items` belonging to the given sales.
  Future<List<Map<String, dynamic>>> fetchSaleItems({
    required List<String> saleIds,
  }) async {
    if (saleIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final SupabaseClient client = _requireClient();
    final List<Map<String, dynamic>> allRows = <Map<String, dynamic>>[];

    for (int i = 0; i < saleIds.length; i += inFilterChunkSize) {
      final int end = (i + inFilterChunkSize < saleIds.length)
          ? i + inFilterChunkSize
          : saleIds.length;
      final List<String> chunk = saleIds.sublist(i, end);

      final List<Map<String, dynamic>> rows = await client
          .from('sale_items')
          .select('product_id, quantity, unit_price, line_total, sale_id')
          .inFilter('sale_id', chunk);

      allRows.addAll(rows);
    }

    return allRows;
  }

  // ===========================================================================
  // RETURNS
  // ===========================================================================

  /// Fetches confirmed returns for the period.
  Future<List<Map<String, dynamic>>> fetchReturns({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('sale_returns')
        .select('id, total, status, return_date')
        .eq('company_id', companyId)
        .eq('status', 'confirmed');

    if (fromDate != null) {
      query = query.gte('return_date', _formatDateOnly(fromDate));
    }
    if (toDate != null) {
      query = query.lte('return_date', _formatDateOnly(toDate));
    }

    final List<Map<String, dynamic>> rows =
        await query.limit(safetyLimit);
    return rows;
  }

  // ===========================================================================
  // Internal helpers
  // ===========================================================================

  SupabaseClient _requireClient() {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const ReportException(
        type: ReportFailureType.unknown,
        cause: 'Supabase client is not initialised.',
      );
    }
    return client;
  }

  static String _formatTimestamp(DateTime value) =>
      value.toUtc().toIso8601String();

  static String _formatDateOnly(DateTime value) {
    final DateTime local = value.toLocal();
    final String y = local.year.toString().padLeft(4, '0');
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
