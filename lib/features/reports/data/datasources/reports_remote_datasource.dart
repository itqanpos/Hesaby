// lib/features/reports/data/datasources/reports_remote_datasource.dart

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../../domain/repositories/reports_repository.dart';

/// Thin wrapper over the Supabase queries the reports feature needs.
class ReportsRemoteDataSource {
  const ReportsRemoteDataSource(this._client);

  final SupabaseClient? _client;

  bool get isAvailable => _client != null;

  static const int safetyLimit = 5000;
  static const int saleItemsSafetyLimit = 50000;
  static const int inFilterChunkSize = 150;

  /// PostgREST returns at most one page per request (server max rows, often
  /// 1000). Requesting a bare `limit` silently truncates results. This pages
  /// through all rows; the caller must supply a deterministic `order`.
  static const int _pageSize = 1000;

  static Future<List<Map<String, dynamic>>> _pageAll(
    Future<List<Map<String, dynamic>>> Function(int from, int to) fetchPage,
  ) async {
    final List<Map<String, dynamic>> all = <Map<String, dynamic>>[];
    int from = 0;
    while (true) {
      final List<Map<String, dynamic>> rows =
          await fetchPage(from, from + _pageSize - 1);
      all.addAll(rows);
      if (rows.length < _pageSize) break;
      from += _pageSize;
    }
    return all;
  }

  /// The movement types that contribute to the *cost* side of a sale.
  ///
  /// `sale_out` moves stock out with a **negative** quantity.
  /// `return_in` moves stock back in with a **positive** quantity.
  static const List<String> _costMovementTypes = <String>[
    'sale_out',
    'return_in',
  ];

  // ===========================================================================
  // SALES
  // ===========================================================================

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

    if (limit != null && limit > 0) {
      return await query.limit(limit);
    }

    // بلا حد: ترقيم كامل كي تكون المجاميع كاملة (لا اقتطاع صامت).
    return _pageAll((int from, int to) {
      var paged = client
          .from('sales')
          .select(
            'id, status, total, paid_amount, discount, tax_amount, '
            'customer_id, created_by, sale_date',
          )
          .eq('company_id', companyId);
      if (fromDate != null) {
        paged = paged.gte('sale_date', _formatTimestamp(fromDate));
      }
      if (toDate != null) {
        paged = paged.lte('sale_date', _formatTimestamp(toDate));
      }
      return paged.order('id').range(from, to);
    });
  }

  Future<List<String>> fetchConfirmedSaleIds({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    final List<Map<String, dynamic>> rows = await _pageAll(
      (int from, int to) {
        var paged = client
            .from('sales')
            .select('id')
            .eq('company_id', companyId)
            .eq('status', 'confirmed');
        if (fromDate != null) {
          paged = paged.gte('sale_date', _formatTimestamp(fromDate));
        }
        if (toDate != null) {
          paged = paged.lte('sale_date', _formatTimestamp(toDate));
        }
        return paged.order('id').range(from, to);
      },
    );

    return rows
        .map((Map<String, dynamic> r) => r['id'])
        .whereType<String>()
        .toList(growable: false);
  }

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

      final List<Map<String, dynamic>> rows = await _pageAll(
        (int from, int to) => client
            .from('sale_items')
            .select('product_id, quantity, unit_price, line_total, sale_id')
            .inFilter('sale_id', chunk)
            .order('id')
            .range(from, to),
      );

      allRows.addAll(rows);
    }

    return allRows;
  }

  Future<List<Map<String, dynamic>>> fetchConfirmedSalesForCustomers({
    required String companyId,
    required List<String> customerIds,
  }) async {
    if (customerIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final SupabaseClient client = _requireClient();
    final List<Map<String, dynamic>> allRows = <Map<String, dynamic>>[];

    for (int i = 0; i < customerIds.length; i += inFilterChunkSize) {
      final int end = (i + inFilterChunkSize < customerIds.length)
          ? i + inFilterChunkSize
          : customerIds.length;
      final List<String> chunk = customerIds.sublist(i, end);

      final List<Map<String, dynamic>> rows = await _pageAll(
        (int from, int to) => client
            .from('sales')
            .select('customer_id, sale_date, total')
            .eq('company_id', companyId)
            .eq('status', 'confirmed')
            .inFilter('customer_id', chunk)
            .order('id')
            .range(from, to),
      );

      allRows.addAll(rows);
    }

    return allRows;
  }

  // ===========================================================================
  // CUSTOMER PAYMENTS
  // ===========================================================================

  Future<List<Map<String, dynamic>>> fetchCustomerPayments({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('customer_payments')
        .select('customer_id, amount, created_at')
        .eq('company_id', companyId);

    if (fromDate != null) {
      query = query.gte('created_at', _formatTimestamp(fromDate));
    }
    if (toDate != null) {
      query = query.lte('created_at', _formatTimestamp(toDate));
    }

    return await query.limit(safetyLimit);
  }

  // ===========================================================================
  // RETURNS
  // ===========================================================================

  Future<List<Map<String, dynamic>>> fetchReturns({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    return _pageAll((int from, int to) {
      var paged = client
          .from('sale_returns')
          .select('id, total, status, return_date')
          .eq('company_id', companyId)
          .eq('status', 'confirmed');
      if (fromDate != null) {
        paged = paged.gte('return_date', _formatDateOnly(fromDate));
      }
      if (toDate != null) {
        paged = paged.lte('return_date', _formatDateOnly(toDate));
      }
      return paged.order('id').range(from, to);
    });
  }

  // ===========================================================================
  // INVENTORY
  // ===========================================================================

  Future<List<Map<String, dynamic>>> fetchInventoryBalances({
    required String companyId,
    String? branchId,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('inventory_balances')
        .select('product_id, branch_id, quantity_on_hand, average_cost')
        .eq('company_id', companyId)
        .gt('quantity_on_hand', 0);

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }

    return await query.limit(safetyLimit);
  }

  Future<List<Map<String, dynamic>>> fetchProductsWithMinStock({
    required String companyId,
  }) async {
    final SupabaseClient client = _requireClient();

    return await client
        .from('products')
        .select('id, name, default_unit_id, min_stock')
        .eq('company_id', companyId)
        .not('min_stock', 'is', null)
        .limit(safetyLimit);
  }

  Future<Map<String, DateTime>> fetchLastSoldDateByProduct({
    required String companyId,
    required List<String> productIds,
  }) async {
    if (productIds.isEmpty) {
      return const <String, DateTime>{};
    }

    final SupabaseClient client = _requireClient();
    final Map<String, DateTime> result = <String, DateTime>{};

    for (int i = 0; i < productIds.length; i += inFilterChunkSize) {
      final int end = (i + inFilterChunkSize < productIds.length)
          ? i + inFilterChunkSize
          : productIds.length;
      final List<String> chunk = productIds.sublist(i, end);

      final List<Map<String, dynamic>> rows = await client
          .from('sale_items')
          .select('product_id, sales!inner(sale_date, status, company_id)')
          .eq('sales.company_id', companyId)
          .eq('sales.status', 'confirmed')
          .inFilter('product_id', chunk)
          .limit(saleItemsSafetyLimit);

      for (final Map<String, dynamic> row in rows) {
        final Object? pidRaw = row['product_id'];
        final Object? saleRaw = row['sales'];
        if (pidRaw is! String || saleRaw is! Map) continue;
        final Object? dateRaw =
            (saleRaw as Map<String, dynamic>)['sale_date'];
        if (dateRaw is! String) continue;
        final DateTime? parsed = DateTime.tryParse(dateRaw);
        if (parsed == null) continue;
        final DateTime utc = parsed.toUtc();
        final DateTime? existing = result[pidRaw];
        if (existing == null || utc.isAfter(existing)) {
          result[pidRaw] = utc;
        }
      }
    }

    return result;
  }

  // ===========================================================================
  // FINANCIAL
  // ===========================================================================

  Future<List<Map<String, dynamic>>> fetchSaleCostMovements({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('stock_movements')
        .select(
          'product_id, quantity, unit_cost, created_at, '
          'reference_id, movement_type',
        )
        .eq('company_id', companyId)
        .inFilter('movement_type', _costMovementTypes);

    if (fromDate != null) {
      query = query.gte('created_at', _formatTimestamp(fromDate));
    }
    if (toDate != null) {
      query = query.lte('created_at', _formatTimestamp(toDate));
    }

    return await query.limit(safetyLimit);
  }

  Future<List<Map<String, dynamic>>> fetchCustomersWithBalance({
    required String companyId,
  }) async {
    final SupabaseClient client = _requireClient();

    return await client
        .from('customers')
        .select('id, name, phone, balance')
        .eq('company_id', companyId)
        .gt('balance', 0)
        .order('balance', ascending: false)
        .limit(safetyLimit);
  }

  /// NOTE: `purchases` has NO `paid_amount` column. Every payment
  /// (whether linked to a purchase via `purchase_id` or standalone)
  /// lives in `supplier_payments`. The repository sums the payments
  /// separately and combines them with the totals returned here.
  Future<List<Map<String, dynamic>>> fetchPurchases({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('purchases')
        .select('id, supplier_id, total, status, purchase_date')
        .eq('company_id', companyId)
        .eq('status', 'confirmed');

    if (fromDate != null) {
      query = query.gte('purchase_date', _formatDateOnly(fromDate));
    }
    if (toDate != null) {
      query = query.lte('purchase_date', _formatDateOnly(toDate));
    }

    return await query.limit(safetyLimit);
  }

  Future<List<Map<String, dynamic>>> fetchConfirmedPurchasesForSuppliers({
    required String companyId,
    required List<String> supplierIds,
  }) async {
    if (supplierIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final SupabaseClient client = _requireClient();
    final List<Map<String, dynamic>> allRows = <Map<String, dynamic>>[];

    for (int i = 0; i < supplierIds.length; i += inFilterChunkSize) {
      final int end = (i + inFilterChunkSize < supplierIds.length)
          ? i + inFilterChunkSize
          : supplierIds.length;
      final List<String> chunk = supplierIds.sublist(i, end);

      final List<Map<String, dynamic>> rows = await client
          .from('purchases')
          .select('supplier_id, purchase_date, total')
          .eq('company_id', companyId)
          .eq('status', 'confirmed')
          .inFilter('supplier_id', chunk)
          .limit(safetyLimit);

      allRows.addAll(rows);
    }

    return allRows;
  }

  Future<List<Map<String, dynamic>>> fetchSupplierPayments({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('supplier_payments')
        .select('supplier_id, amount, payment_date')
        .eq('company_id', companyId);

    if (fromDate != null) {
      query = query.gte('payment_date', _formatDateOnly(fromDate));
    }
    if (toDate != null) {
      query = query.lte('payment_date', _formatDateOnly(toDate));
    }

    return await query.limit(safetyLimit);
  }

  Future<List<Map<String, dynamic>>> fetchPaymentsForSuppliers({
    required String companyId,
    required List<String> supplierIds,
  }) async {
    if (supplierIds.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final SupabaseClient client = _requireClient();
    final List<Map<String, dynamic>> allRows = <Map<String, dynamic>>[];

    for (int i = 0; i < supplierIds.length; i += inFilterChunkSize) {
      final int end = (i + inFilterChunkSize < supplierIds.length)
          ? i + inFilterChunkSize
          : supplierIds.length;
      final List<String> chunk = supplierIds.sublist(i, end);

      final List<Map<String, dynamic>> rows = await client
          .from('supplier_payments')
          .select('supplier_id, amount')
          .eq('company_id', companyId)
          .inFilter('supplier_id', chunk)
          .limit(safetyLimit);

      allRows.addAll(rows);
    }

    return allRows;
  }

  Future<List<Map<String, dynamic>>> fetchAllSuppliers({
    required String companyId,
  }) async {
    final SupabaseClient client = _requireClient();

    return await client
        .from('suppliers')
        .select('id, name, phone')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .limit(safetyLimit);
  }

  Future<List<Map<String, dynamic>>> fetchExpenses({
    required String companyId,
    required DateTime? fromDate,
    required DateTime? toDate,
  }) async {
    final SupabaseClient client = _requireClient();

    var query = client
        .from('expenses')
        .select('amount, expense_date')
        .eq('company_id', companyId);

    if (fromDate != null) {
      query = query.gte('expense_date', _formatDateOnly(fromDate));
    }
    if (toDate != null) {
      query = query.lte('expense_date', _formatDateOnly(toDate));
    }

    return await query.limit(safetyLimit);
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
