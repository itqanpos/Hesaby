// lib/features/reports/data/repositories/reports_repository_impl.dart

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/aging_reports.dart';
import '../../domain/entities/financial_reports.dart';
import '../../domain/entities/inventory_reports.dart';
import '../../domain/entities/profit_reports.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/sales_reports.dart';
import '../../domain/repositories/reports_repository.dart';
import '../datasources/reports_remote_datasource.dart';

/// Concrete implementation of [ReportsRepository] backed by Supabase.
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
        if (productId.isEmpty) continue;
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
      // Fetch sales AND standalone customer payments in parallel.
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _remoteDataSource.fetchSales(
          companyId: companyId,
          fromDate: period.fromDate,
          toDate: period.toDate,
        ),
        _remoteDataSource.fetchCustomerPayments(
          companyId: companyId,
          fromDate: period.fromDate,
          toDate: period.toDate,
        ),
      ]);

      final List<Map<String, dynamic>> sales =
          (results[0] as List<Map<String, dynamic>>);
      final List<Map<String, dynamic>> payments =
          (results[1] as List<Map<String, dynamic>>);

      // Aggregate sales per customer.
      final Map<String, _CustomerAgg> byCustomer =
          <String, _CustomerAgg>{};

      for (final Map<String, dynamic> row in sales) {
        if (_asString(row['status']) != 'confirmed') continue;
        final String? customerId =
            row['customer_id'] is String ? row['customer_id'] as String : null;
        if (customerId == null || customerId.isEmpty) continue;
        final double total = _asDouble(row['total']);
        final double paid = _asDouble(row['paid_amount']);

        byCustomer
            .putIfAbsent(customerId, () => _CustomerAgg())
            .add(total, paid);
      }

      // Fold standalone customer payments into the paid totals.
      // These payments are not attached to a specific sale; they reduce
      // the customer's running balance directly.
      for (final Map<String, dynamic> row in payments) {
        final String? customerId = row['customer_id'] is String
            ? row['customer_id'] as String
            : null;
        if (customerId == null || customerId.isEmpty) continue;
        final double amount = _asDouble(row['amount']);
        byCustomer
            .putIfAbsent(customerId, () => _CustomerAgg())
            .addStandalonePayment(amount);
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
        if (_asString(row['status']) != 'confirmed') continue;
        final String? createdBy =
            row['created_by'] is String ? row['created_by'] as String : null;
        final String key = createdBy ?? '__unknown__';
        final double total = _asDouble(row['total']);
        final double paid = _asDouble(row['paid_amount']);
        byCashier.putIfAbsent(key, () => _CashierAgg()).add(total, paid);
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
  // Profit & Loss
  // ---------------------------------------------------------------------------

  @override
  Future<ProfitLossSummary> getProfitLoss({
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
        _remoteDataSource.fetchSaleCostMovements(
          companyId: companyId,
          fromDate: period.fromDate,
          toDate: period.toDate,
        ),
        _remoteDataSource.fetchExpenses(
          companyId: companyId,
          fromDate: period.fromDate,
          toDate: period.toDate,
        ),
      ]);

      final List<Map<String, dynamic>> sales =
          (results[0] as List<Map<String, dynamic>>);
      final List<Map<String, dynamic>> returns =
          (results[1] as List<Map<String, dynamic>>);
      final List<Map<String, dynamic>> movements =
          (results[2] as List<Map<String, dynamic>>);
      final List<Map<String, dynamic>> expenseRows =
          (results[3] as List<Map<String, dynamic>>);

      double grossRevenue = 0;
      for (final Map<String, dynamic> row in sales) {
        if (_asString(row['status']) == 'confirmed') {
          grossRevenue += _asDouble(row['total']);
        }
      }

      double returnTotal = 0;
      for (final Map<String, dynamic> row in returns) {
        returnTotal += _asDouble(row['total']);
      }

      // Cost of goods sold, net of returns.
      // `movement_type` decides the sign of the contribution; the sign of
      // `quantity` is ignored (see reports_remote_datasource.dart).
      double cogs = 0;
      for (final Map<String, dynamic> row in movements) {
        final String type = _asString(row['movement_type']);
        final double qty = _asDouble(row['quantity']);
        final double cost = _asDouble(row['unit_cost']);
        final double absQty = qty < 0 ? -qty : qty;
        if (type == 'return_in') {
          cogs -= absQty * cost;
        } else {
          cogs += absQty * cost;
        }
      }

      double operatingExpenses = 0;
      for (final Map<String, dynamic> row in expenseRows) {
        operatingExpenses += _asDouble(row['amount']);
      }

      final double netRevenue = grossRevenue - returnTotal;
      final double grossProfit = netRevenue - cogs;

      return ProfitLossSummary(
        period: period,
        grossRevenue: grossRevenue,
        returnTotal: returnTotal,
        netRevenue: netRevenue,
        costOfGoodsSold: cogs,
        grossProfit: grossProfit,
        operatingExpenses: operatingExpenses,
      );
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getProfitLoss');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getProfitLoss');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getProfitLoss');
    }
  }

  // ---------------------------------------------------------------------------
  // Per-product profit
  // ---------------------------------------------------------------------------

  @override
  Future<ProductProfitReport> getProductProfit({
    required String companyId,
    required ReportPeriod period,
    required Map<String, String> productNames,
  }) async {
    try {
      final List<String> saleIds =
          await _remoteDataSource.fetchConfirmedSaleIds(
        companyId: companyId,
        fromDate: period.fromDate,
        toDate: period.toDate,
      );

      final List<Map<String, dynamic>> movements =
          await _remoteDataSource.fetchSaleCostMovements(
        companyId: companyId,
        fromDate: period.fromDate,
        toDate: period.toDate,
      );

      if (saleIds.isEmpty && movements.isEmpty) {
        return ProductProfitReport.empty();
      }

      final Map<String, _ProfitAgg> byProduct = <String, _ProfitAgg>{};

      if (saleIds.isNotEmpty) {
        final List<Map<String, dynamic>> items =
            await _remoteDataSource.fetchSaleItems(saleIds: saleIds);

        for (final Map<String, dynamic> row in items) {
          final String productId = _asString(row['product_id']);
          if (productId.isEmpty) continue;
          final double qty = _asDouble(row['quantity']);
          final double revenue = _asDouble(row['line_total']);
          final String saleId = _asString(row['sale_id']);
          byProduct
              .putIfAbsent(productId, () => _ProfitAgg())
              .addSale(qty, revenue, saleId);
        }
      }

      // Signed cost per product, using movement_type (see P&L above).
      for (final Map<String, dynamic> row in movements) {
        final String productId = _asString(row['product_id']);
        if (productId.isEmpty) continue;
        final String type = _asString(row['movement_type']);
        final double qty = _asDouble(row['quantity']);
        final double unitCost = _asDouble(row['unit_cost']);
        final double absQty = qty < 0 ? -qty : qty;
        final double signedCost = type == 'return_in'
            ? -(absQty * unitCost)
            : (absQty * unitCost);
        byProduct
            .putIfAbsent(productId, () => _ProfitAgg())
            .addCost(signedCost);
      }

      final List<ProductProfit> items = <ProductProfit>[];
      double totalRevenue = 0;
      double totalCost = 0;
      int productsWithLoss = 0;

      byProduct.forEach((String pid, _ProfitAgg agg) {
        final ProductProfit p = ProductProfit(
          productId: pid,
          productName: productNames[pid] ?? 'منتج محذوف',
          quantitySold: agg.quantity,
          revenue: agg.revenue,
          cost: agg.cost,
          invoiceCount: agg.saleIds.length,
        );
        items.add(p);
        totalRevenue += p.revenue;
        totalCost += p.cost;
        if (p.profit < 0) productsWithLoss++;
      });

      items.sort((ProductProfit a, ProductProfit b) =>
          b.profit.compareTo(a.profit));

      return ProductProfitReport(
        items: items,
        totalRevenue: totalRevenue,
        totalCost: totalCost,
        productsWithLoss: productsWithLoss,
      );
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getProductProfit');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getProductProfit');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getProductProfit');
    }
  }

  // ---------------------------------------------------------------------------
  // Receivables
  // ---------------------------------------------------------------------------

  @override
  Future<ReceivablesReport> getReceivables({
    required String companyId,
  }) async {
    try {
      final List<Map<String, dynamic>> rows =
          await _remoteDataSource.fetchCustomersWithBalance(
        companyId: companyId,
      );

      if (rows.isEmpty) {
        return ReceivablesReport.empty();
      }

      double totalBalance = 0;
      final List<ReceivableItem> items = <ReceivableItem>[];
      for (final Map<String, dynamic> row in rows) {
        final String cid = _asString(row['id']);
        if (cid.isEmpty) continue;
        final double balance = _asDouble(row['balance']);
        if (balance <= 0) continue;
        totalBalance += balance;

        final String? phone = row['phone'] is String
            ? (row['phone'] as String).trim()
            : null;

        items.add(
          ReceivableItem(
            customerId: cid,
            customerName: _asString(row['name']).isNotEmpty
                ? _asString(row['name'])
                : 'عميل محذوف',
            balance: balance,
            phone: (phone == null || phone.isEmpty) ? null : phone,
          ),
        );
      }

      return ReceivablesReport(
        items: items,
        totalBalance: totalBalance,
        customerCount: items.length,
      );
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getReceivables');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getReceivables');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getReceivables');
    }
  }

  // ---------------------------------------------------------------------------
  // Payables
  // ---------------------------------------------------------------------------

  @override
  Future<PayablesReport> getPayables({
    required String companyId,
    required ReportPeriod period,
    required Map<String, String> supplierNames,
  }) async {
    try {
      // Fetch purchases AND standalone supplier payments in parallel.
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _remoteDataSource.fetchPurchases(
          companyId: companyId,
          fromDate: period.fromDate,
          toDate: period.toDate,
        ),
        _remoteDataSource.fetchSupplierPayments(
          companyId: companyId,
          fromDate: period.fromDate,
          toDate: period.toDate,
        ),
      ]);

      final List<Map<String, dynamic>> rows =
          (results[0] as List<Map<String, dynamic>>);
      final List<Map<String, dynamic>> standalonePayments =
          (results[1] as List<Map<String, dynamic>>);

      if (rows.isEmpty && standalonePayments.isEmpty) {
        return PayablesReport.empty(period);
      }

      final Map<String, _SupplierAgg> bySupplier =
          <String, _SupplierAgg>{};

      for (final Map<String, dynamic> row in rows) {
        final String? sid = row['supplier_id'] is String
            ? row['supplier_id'] as String
            : null;
        if (sid == null || sid.isEmpty) continue;

        bySupplier
            .putIfAbsent(sid, () => _SupplierAgg())
            .add(
              _asDouble(row['total']),
              _asDouble(row['paid_amount']),
            );
      }

      // Fold standalone supplier payments into the paid totals.
      for (final Map<String, dynamic> row in standalonePayments) {
        final String? sid = row['supplier_id'] is String
            ? row['supplier_id'] as String
            : null;
        if (sid == null || sid.isEmpty) continue;
        final double amount = _asDouble(row['amount']);
        bySupplier
            .putIfAbsent(sid, () => _SupplierAgg())
            .addStandalonePayment(amount);
      }

      final List<PayableItem> items = bySupplier.entries.map(
        (MapEntry<String, _SupplierAgg> e) {
          return PayableItem(
            supplierId: e.key,
            supplierName: supplierNames[e.key] ?? 'مورد محذوف',
            invoiceCount: e.value.count,
            totalPurchases: e.value.purchases,
            totalPaid: e.value.paid,
            totalDue: e.value.purchases - e.value.paid,
          );
        },
      ).toList();

      items.sort((PayableItem a, PayableItem b) =>
          b.totalDue.compareTo(a.totalDue));

      double totalPurchases = 0;
      double totalPaid = 0;
      for (final PayableItem it in items) {
        totalPurchases += it.totalPurchases;
        totalPaid += it.totalPaid;
      }

      return PayablesReport(
        period: period,
        items: items,
        totalPurchases: totalPurchases,
        totalPaid: totalPaid,
        totalDue: totalPurchases - totalPaid,
      );
    } on ReportException {
      rethrow;
    } on supabase.PostgrestException catch (error, stackTrace) {
      throw _mapPostgrest(error, stackTrace, operation: 'getPayables');
    } on supabase.AuthException catch (error, stackTrace) {
      throw _mapAuth(error, stackTrace, operation: 'getPayables');
    } on Object catch (error, stackTrace) {
      throw _mapUnknown(error, stackTrace, operation: 'getPayables');
    }
  }

  // ---------------------------------------------------------------------------
  // Customer aging
  // ---------------------------------------------------------------------------

  @override
  Future<AgingReport> getCustomerAging({
    required String companyId,
  }) async {
    try {
      final List<Map<String, dynamic>> customerRows =
          await _remoteDataSource.fetchCustomersWithBalance(
        companyId: companyId,
      );

      if (customerRows.isEmpty) {
        return AgingReport.empty();
      }

      final Map<String, _AgingCustomer> customers =
          <String, _AgingCustomer>{};
      for (final Map<String, dynamic> row in customerRows) {
        final String id = _asString(row['id']);
        if (id.isEmpty) continue;
        customers[id] = _AgingCustomer(
          id: id,
          name: _asString(row['name']),
          phone: _asNullableString(row['phone']),
          balance: _asDouble(row['balance']),
        );
      }

      if (customers.isEmpty) {
        return AgingReport.empty();
      }

      final List<Map<String, dynamic>> saleRows =
          await _remoteDataSource.fetchConfirmedSalesForCustomers(
        companyId: companyId,
        customerIds: customers.keys.toList(growable: false),
      );

      final Map<String, List<_AgingSale>> salesByCustomer =
          <String, List<_AgingSale>>{};
      for (final Map<String, dynamic> row in saleRows) {
        final String? cid = _asNullableString(row['customer_id']);
        if (cid == null) continue;
        salesByCustomer
            .putIfAbsent(cid, () => <_AgingSale>[])
            .add(
              _AgingSale(
                date: _asDate(row['sale_date']),
                total: _asDouble(row['total']),
              ),
            );
      }
      for (final List<_AgingSale> list in salesByCustomer.values) {
        list.sort((_AgingSale a, _AgingSale b) => a.date.compareTo(b.date));
      }

      final DateTime now = DateTime.now().toUtc();
      final List<CustomerAgingRow> rows = <CustomerAgingRow>[];

      for (final _AgingCustomer customer in customers.values) {
        final List<_AgingSale> sales =
            salesByCustomer[customer.id] ?? const <_AgingSale>[];

        double remaining = customer.balance;
        double b0to30 = 0;
        double b31to60 = 0;
        double b61to90 = 0;
        double b90plus = 0;

        for (final _AgingSale sale in sales) {
          if (remaining <= 0) break;
          final double allocated =
              remaining < sale.total ? remaining : sale.total;
          remaining -= allocated;

          final int days = now.difference(sale.date).inDays;
          if (days <= 30) {
            b0to30 += allocated;
          } else if (days <= 60) {
            b31to60 += allocated;
          } else if (days <= 90) {
            b61to90 += allocated;
          } else {
            b90plus += allocated;
          }
        }

        if (remaining > 0) {
          b90plus += remaining;
        }

        rows.add(
          CustomerAgingRow(
            customerId: customer.id,
            customerName:
                customer.name.isEmpty ? 'عميل محذوف' : customer.name,
            phone: customer.phone,
            balance: customer.balance,
            buckets: AgingBuckets(
              days0to30: b
