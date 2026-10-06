// lib/features/reports/data/repositories/reports_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/inventory_reports.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/sales_reports.dart';
import '../../domain/repositories/reports_repository.dart';
import '../datasources/reports_remote_datasource.dart';

/// Concrete implementation of [ReportsRepository] backed by Supabase.
///
/// Strategy:
/// * One narrow query per aggregation source (sales, sale_items, returns,
///   inventory_balances, products).
/// * Filtering happens in SQL; grouping and derived metrics happen here.
/// * Only confirmed sales and returns contribute to the sales totals.
/// * Inventory reports operate on the *current* state (no period).
class ReportsRepositoryImpl implements ReportsRepository {
  const ReportsRepositoryImpl(this._remoteDataSource);

  final ReportsRemoteDataSource _remoteDataSource;

  // ---------------------------------------------------------------------------
  // Sales summary
  // ---------------------------------------------------------------------------

  @override
  Future<SalesSummary> getSalesSummary({
    required String companyId,
    required ReportPeriod period,
  }) async {
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _remoteDataSource.fetchSales(
          companyId: companyId,
          fromDate: period.fromDate,
          toDate: period.toDate,
        ),
        _remoteDataSource.fetchReturns(
          companyId: companyId,
          fromDate: period.fromDate,
          toDate: period.toDate,
        ),
      ]);

      final List<Map<String, dynamic>> sales =
          (results[0] as List<Map<String, dynamic>>);
      final List<Map<String, dynamic>> returns =
          (results[1] as List<Map<String, dynamic>>);

      int confirmedCount = 0;
      int draftCount = 0;
      int cancelledCount = 0;
      double totalSales = 0;
      double totalPaid = 0;
      double totalDue = 0;
      double totalDiscount = 0;
      double totalTax = 0;

      for (final Map<String, dynamic> row in sales) {
        final String status = _asString(row['status']);
        switch (status) {
          case 'confirmed':
            confirmedCount++;
            final double total = _asDouble(row['total']);
            final double paid = _asDouble(row['paid_amount']);
            totalSales += total;
            totalPaid += paid;
            final double due = total - paid;
            if (due > 0) totalDue += due;
            totalDiscount += _asDouble(row['discount']);
            totalTax += _asDouble(row['tax_amount']);
          case 'draft':
            draftCount++;
          case 'cancelled':
            cancelledCount++;
        }
      }

      int returnCount = 0;
      double returnTotal = 0;
      for (final Map<String, dynamic> row in returns) {
        returnCount++;
        returnTotal += _asDouble(row['total']);
      }

      return SalesSummary(
        period: period,
        confirmedCount: confirmedCount,
        draftCount: draftCount,
        cancelledCount: cancelledCount,
        totalSales: totalSales,
        totalPaid: totalPaid,
        totalDue: totalDue,
        totalDiscount: totalDiscount,
        totalTax: totalTax,
        returnCount: returnCount,
        returnTotal: returnTotal,
      );
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getSalesSummary');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getSalesSummary');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getSalesSummary');
    }
  }

  // ---------------------------------------------------------------------------
  // Top products
  // ---------------------------------------------------------------------------

  @override
  Future<List<TopProduct>> getTopProducts({
    required String companyId,
    required ReportPeriod period,
    int limit = 20,
    required Map<String, String> productNames,
  }) async {
    try {
      final List<String> saleIds =
          await _remoteDataSource.fetchConfirmedSaleIds(
        companyId: companyId,
        fromDate: period.fromDate,
        toDate: period.toDate,
      );

      if (saleIds.isEmpty) {
        return const <TopProduct>[];
      }

      final List<Map<String, dynamic>> items =
          await _remoteDataSource.fetchSaleItems(saleIds: saleIds);

      final Map<String, _ProductAgg> byProduct = <String, _ProductAgg>{};
      for (final Map<String, dynamic> row in items) {
        final String productId = _asString(row['product_id']);
        if (productId.isEmpty) {
          continue;
        }
        final double qty = _asDouble(row['quantity']);
        final double revenue = _asDouble(row['line_total']);
        final String saleId = _asString(row['sale_id']);

        byProduct
            .putIfAbsent(productId, () => _ProductAgg())
            .add(qty, revenue, saleId);
      }

      final List<TopProduct> all = byProduct.entries.map(
        (MapEntry<String, _ProductAgg> e) {
          return TopProduct(
            productId: e.key,
            productName: productNames[e.key] ?? 'منتج محذوف',
            totalQuantity: e.value.quantity,
            totalRevenue: e.value.revenue,
            invoiceCount: e.value.saleIds.length,
          );
        },
      ).toList();

      all.sort((TopProduct a, TopProduct b) =>
          b.totalRevenue.compareTo(a.totalRevenue));

      return all.take(limit).toList(growable: false);
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getTopProducts');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getTopProducts');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getTopProducts');
    }
  }

  // ---------------------------------------------------------------------------
  // Top customers
  // ---------------------------------------------------------------------------

  @override
  Future<List<TopCustomer>> getTopCustomers({
    required String companyId,
    required ReportPeriod period,
    int limit = 20,
    required Map<String, String> customerNames,
  }) async {
    try {
      final List<Map<String, dynamic>> sales =
          await _remoteDataSource.fetchSales(
        companyId: companyId,
        fromDate: period.fromDate,
        toDate: period.toDate,
      );

      final Map<String, _CustomerAgg> byCustomer =
          <String, _CustomerAgg>{};

      for (final Map<String, dynamic> row in sales) {
        if (_asString(row['status']) != 'confirmed') {
          continue;
        }
        final String? customerId =
            row['customer_id'] is String ? row['customer_id'] as String : null;
        if (customerId == null || customerId.isEmpty) {
          continue;
        }
        final double total = _asDouble(row['total']);
        final double paid = _asDouble(row['paid_amount']);

        byCustomer
            .putIfAbsent(customerId, () => _CustomerAgg())
            .add(total, paid);
      }

      final List<TopCustomer> all = byCustomer.entries.map(
        (MapEntry<String, _CustomerAgg> e) {
          return TopCustomer(
            customerId: e.key,
            customerName: customerNames[e.key] ?? 'عميل محذوف',
            invoiceCount: e.value.count,
            totalSpent: e.value.spent,
            totalPaid: e.value.paid,
            totalDue: e.value.spent - e.value.paid,
          );
        },
      ).toList();

      all.sort((TopCustomer a, TopCustomer b) =>
          b.totalSpent.compareTo(a.totalSpent));

      return all.take(limit).toList(growable: false);
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getTopCustomers');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getTopCustomers');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getTopCustomers');
    }
  }

  // ---------------------------------------------------------------------------
  // Sales by cashier
  // ---------------------------------------------------------------------------

  @override
  Future<List<CashierSales>> getSalesByCashier({
    required String companyId,
    required ReportPeriod period,
    required Map<String, String> cashierNames,
  }) async {
    try {
      final List<Map<String, dynamic>> sales =
          await _remoteDataSource.fetchSales(
        companyId: companyId,
        fromDate: period.fromDate,
        toDate: period.toDate,
      );

      final Map<String, _CashierAgg> byCashier = <String, _CashierAgg>{};

      for (final Map<String, dynamic> row in sales) {
        if (_asString(row['status']) != 'confirmed') {
          continue;
        }
        final String? createdBy =
            row['created_by'] is String ? row['created_by'] as String : null;
        final String key = createdBy ?? '__unknown__';

        final double total = _asDouble(row['total']);
        final double paid = _asDouble(row['paid_amount']);

        byCashier
            .putIfAbsent(key, () => _CashierAgg())
            .add(total, paid);
      }

      final List<CashierSales> all = byCashier.entries.map(
        (MapEntry<String, _CashierAgg> e) {
          final String name = e.key == '__unknown__'
              ? 'غير معروف'
              : (cashierNames[e.key] ?? _shortId(e.key));
          return CashierSales(
            cashierId: e.key,
            cashierName: name,
            invoiceCount: e.value.count,
            totalSales: e.value.sales,
            totalPaid: e.value.paid,
            totalDue: e.value.sales - e.value.paid,
          );
        },
      ).toList();

      all.sort((CashierSales a, CashierSales b) =>
          b.totalSales.compareTo(a.totalSales));

      return all;
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getSalesByCashier');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getSalesByCashier');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getSalesByCashier');
    }
  }

  // ---------------------------------------------------------------------------
  // Stock valuation
  // ---------------------------------------------------------------------------

  @override
  Future<StockValuationReport> getStockValuation({
    required String companyId,
    String? branchId,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  }) async {
    try {
      final List<Map<String, dynamic>> rows =
          await _remoteDataSource.fetchInventoryBalances(
        companyId: companyId,
        branchId: branchId,
      );

      if (rows.isEmpty) {
        return StockValuationReport.empty();
      }

      // Aggregate per product across branches.
      final Map<String, _ValuationAgg> byProduct =
          <String, _ValuationAgg>{};

      for (final Map<String, dynamic> row in rows) {
        final String productId = _asString(row['product_id']);
        if (productId.isEmpty) continue;
        final double qty = _asDouble(row['quantity_on_hand']);
        final double cost = _asDouble(row['average_cost']);
        byProduct
            .putIfAbsent(productId, () => _ValuationAgg())
            .add(qty, cost * qty);
      }

      final List<StockValuationItem> items = byProduct.entries.map(
        (MapEntry<String, _ValuationAgg> e) {
          final _ValuationAgg agg = e.value;
          final double weightedCost =
              agg.quantity > 0 ? agg.costValue / agg.quantity : 0;
          return StockValuationItem(
            productId: e.key,
            productName: productNames[e.key] ?? 'منتج محذوف',
            quantityOnHand: agg.quantity,
            averageCost: weightedCost,
            totalValue: agg.costValue,
            unitName: unitNames[e.key],
          );
        },
      ).toList();

      items.sort((StockValuationItem a, StockValuationItem b) =>
          b.totalValue.compareTo(a.totalValue));

      double totalValue = 0;
      double totalQuantity = 0;
      for (final StockValuationItem it in items) {
        totalValue += it.totalValue;
        totalQuantity += it.quantityOnHand;
      }

      return StockValuationReport(
        items: items,
        totalValue: totalValue,
        totalQuantity: totalQuantity,
      );
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getStockValuation');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getStockValuation');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getStockValuation');
    }
  }

  // ---------------------------------------------------------------------------
  // Low stock
  // ---------------------------------------------------------------------------

  @override
  Future<List<LowStockItem>> getLowStockItems({
    required String companyId,
    String? branchId,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  }) async {
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _remoteDataSource.fetchProductsWithMinStock(companyId: companyId),
        _remoteDataSource.fetchInventoryBalances(
          companyId: companyId,
          branchId: branchId,
        ),
      ]);

      final List<Map<String, dynamic>> products =
          (results[0] as List<Map<String, dynamic>>);
      final List<Map<String, dynamic>> balances =
          (results[1] as List<Map<String, dynamic>>);

      // Sum on-hand quantity per product.
      final Map<String, double> quantityByProduct = <String, double>{};
      for (final Map<String, dynamic> row in balances) {
        final String pid = _asString(row['product_id']);
        if (pid.isEmpty) continue;
        quantityByProduct[pid] =
            (quantityByProduct[pid] ?? 0) + _asDouble(row['quantity_on_hand']);
      }

      final List<LowStockItem> items = <LowStockItem>[];
      for (final Map<String, dynamic> p in products) {
        final String pid = _asString(p['id']);
        if (pid.isEmpty) continue;
        final double minStock = _asDouble(p['min_stock']);
        if (minStock <= 0) continue;

        final double onHand = quantityByProduct[pid] ?? 0;
        if (onHand > minStock) continue;

        final String rawName = _asString(p['name']);
        items.add(
          LowStockItem(
            productId: pid,
            productName: productNames[pid] ??
                (rawName.isNotEmpty ? rawName : 'منتج محذوف'),
            quantityOnHand: onHand,
            minStock: minStock,
            unitName: unitNames[pid],
          ),
        );
      }

      // Sort by highest deficit first.
      items.sort((LowStockItem a, LowStockItem b) =>
          b.deficit.compareTo(a.deficit));

      return items;
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getLowStockItems');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getLowStockItems');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getLowStockItems');
    }
  }

  // ---------------------------------------------------------------------------
  // Dead stock
  // ---------------------------------------------------------------------------

  @override
  Future<List<DeadStockItem>> getDeadStockItems({
    required String companyId,
    String? branchId,
    required DeadStockWindow window,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
  }) async {
    try {
      final List<Map<String, dynamic>> balances =
          await _remoteDataSource.fetchInventoryBalances(
        companyId: companyId,
        branchId: branchId,
      );

      if (balances.isEmpty) {
        return const <DeadStockItem>[];
      }

      // Aggregate per product.
      final Map<String, _ValuationAgg> byProduct =
          <String, _ValuationAgg>{};
      for (final Map<String, dynamic> row in balances) {
        final String pid = _asString(row['product_id']);
        if (pid.isEmpty) continue;
        final double qty = _asDouble(row['quantity_on_hand']);
        final double cost = _asDouble(row['average_cost']);
        byProduct
            .putIfAbsent(pid, () => _ValuationAgg())
            .add(qty, cost * qty);
      }

      final Map<String, DateTime> lastSold =
          await _remoteDataSource.fetchLastSoldDateByProduct(
        companyId: companyId,
        productIds: byProduct.keys.toList(growable: false),
      );

      final DateTime cutoff = window.cutoff;

      final List<DeadStockItem> items = <DeadStockItem>[];
      byProduct.forEach((String pid, _ValuationAgg agg) {
        final DateTime? last = lastSold[pid];
        final bool dead = last == null || last.isBefore(cutoff);
        if (!dead) return;

        items.add(
          DeadStockItem(
            productId: pid,
            productName: productNames[pid] ?? 'منتج محذوف',
            quantityOnHand: agg.quantity,
            stockValue: agg.costValue,
            lastSoldAt: last,
            unitName: unitNames[pid],
          ),
        );
      });

      // Sort by highest stock value first (the most capital tied up).
      items.sort((DeadStockItem a, DeadStockItem b) =>
          b.stockValue.compareTo(a.stockValue));

      return items;
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getDeadStockItems');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getDeadStockItems');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getDeadStockItems');
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static String _asString(Object? value) {
    if (value is String) return value;
    return value?.toString() ?? '';
  }

  static double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final double? parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static String _shortId(String id) {
    if (id.length <= 6) return id;
    return 'كاشير ${id.substring(id.length - 6)}';
  }
}

// ============================================================================
// Internal aggregation helpers
// ============================================================================

class _ProductAgg {
  double quantity = 0;
  double revenue = 0;
  final Set<String> saleIds = <String>{};

  void add(double qty, double rev, String saleId) {
    quantity += qty;
    revenue += rev;
    if (saleId.isNotEmpty) {
      saleIds.add(saleId);
    }
  }
}

class _CustomerAgg {
  int count = 0;
  double spent = 0;
  double paid = 0;

  void add(double total, double paidAmount) {
    count++;
    spent += total;
    paid += paidAmount;
  }
}

class _CashierAgg {
  int count = 0;
  double sales = 0;
  double paid = 0;

  void add(double total, double paidAmount) {
    count++;
    sales += total;
    paid += paidAmount;
  }
}

/// Accumulator used by both stock valuation and dead stock: tracks total
/// quantity and total cost value per product across all matching balances.
class _ValuationAgg {
  double quantity = 0;
  double costValue = 0;

  void add(double qty, double value) {
    quantity += qty;
    costValue += value;
  }
}

// ============================================================================
// Error mapping
// ============================================================================

ReportException _mapPostgrest(
  supabase.PostgrestException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final ReportFailureType type = _classifyPostgrest(error);
  AppLogger.warning(
    'Report PostgREST error during "$operation" mapped to ${type.name} '
    '(code: ${error.code ?? 'n/a'}).',
  );
  return ReportException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

ReportException _mapAuth(
  supabase.AuthException error,
  StackTrace stackTrace, {
  required String operation,
}) {
  AppLogger.warning(
    'Report auth error during "$operation" mapped to unauthorized '
    '(code: ${error.code ?? 'n/a'}).',
  );
  return ReportException(
    type: ReportFailureType.unauthorized,
    cause: error,
    stackTrace: stackTrace,
  );
}

ReportException _mapUnknown(
  Object error,
  StackTrace stackTrace, {
  required String operation,
}) {
  final ReportFailureType type = _looksLikeNetwork(error)
      ? ReportFailureType.network
      : ReportFailureType.unknown;
  AppLogger.error(
    'Unhandled report error during "$operation" '
    '(runtimeType: ${error.runtimeType}, mapped: ${type.name}).',
    error,
    stackTrace,
  );
  return ReportException(
    type: type,
    cause: error,
    stackTrace: stackTrace,
  );
}

ReportFailureType _classifyPostgrest(supabase.PostgrestException error) {
  final String code = (error.code ?? '').toUpperCase();
  final String message = error.message.toLowerCase();

  if (code == 'PGRST116') {
    return ReportFailureType.notFound;
  }
  if (code.startsWith('42501') || code.startsWith('28')) {
    return ReportFailureType.unauthorized;
  }
  if (code.startsWith('42')) {
    return ReportFailureType.invalidResponse;
  }
  if (message.contains('permission denied') ||
      message.contains('row level security') ||
      message.contains('jwt')) {
    return ReportFailureType.unauthorized;
  }
  if (_looksLikeNetwork(message)) {
    return ReportFailureType.network;
  }
  return ReportFailureType.unknown;
}

bool _looksLikeNetwork(Object error) {
  final String s = error.toString().toLowerCase();
  return s.contains('socket') ||
      s.contains('network') ||
      s.contains('connection') ||
      s.contains('timeout') ||
      s.contains('timed out') ||
      s.contains('unreachable') ||
      s.contains('failed host lookup') ||
      s.contains('clientexception');
}
