// lib/features/reports/presentation/providers/reports_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../data/datasources/reports_remote_datasource.dart';
import '../../data/repositories/reports_repository_impl.dart';
import '../../domain/entities/inventory_reports.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/sales_reports.dart';
import '../../domain/repositories/reports_repository.dart';

// ============================================================================
// Repository provider
// ============================================================================

/// The application's reports repository.
final Provider<ReportsRepository> reportsRepositoryProvider =
    Provider<ReportsRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } on Object {
    client = null;
  }
  return ReportsRepositoryImpl(ReportsRemoteDataSource(client));
});

// ============================================================================
// Shared map builders
// ============================================================================

/// Builds `{productId: productName}` from the current catalogue.
Map<String, String> _buildProductNames(Ref ref) {
  final List<Product> products =
      ref.watch(productsProvider).value ?? const <Product>[];
  return <String, String>{
    for (final Product p in products) p.id: p.name,
  };
}

/// Builds `{productId: defaultUnitName}` from the current catalogue.
///
/// A product's display unit is its `defaultUnitId`; when that unit is
/// missing from the units list, the entry is omitted.
Map<String, String> _buildUnitNamesByProduct(Ref ref) {
  final List<Product> products =
      ref.watch(productsProvider).value ?? const <Product>[];
  final List<Unit> units =
      ref.watch(unitsProvider).value ?? const <Unit>[];

  final Map<String, String> unitNameById = <String, String>{
    for (final Unit u in units) u.id: u.name,
  };

  final Map<String, String> result = <String, String>{};
  for (final Product p in products) {
    final String? maybeUnitId = p.defaultUnitId;
    if (maybeUnitId == null) continue;
    final String name = unitNameById[maybeUnitId] ?? '';
    if (name.isNotEmpty) {
      result[p.id] = name;
    }
  }
  return result;
}

// ============================================================================
// Sales summary
// ============================================================================

/// Sales summary for the currently selected company over [period].
class SalesSummaryNotifier
    extends FamilyAsyncNotifier<SalesSummary, ReportPeriod> {
  @override
  Future<SalesSummary> build(ReportPeriod period) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );

    if (companyId == null) {
      return SalesSummary.empty(period);
    }

    return ref.read(reportsRepositoryProvider).getSalesSummary(
          companyId: companyId,
          period: period,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final salesSummaryProvider = AsyncNotifierProvider.family<
    SalesSummaryNotifier, SalesSummary, ReportPeriod>(
  SalesSummaryNotifier.new,
);

// ============================================================================
// Top products
// ============================================================================

class TopProductsNotifier
    extends FamilyAsyncNotifier<List<TopProduct>, ReportPeriod> {
  @override
  Future<List<TopProduct>> build(ReportPeriod period) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return const <TopProduct>[];
    }

    final Map<String, String> productNames = _buildProductNames(ref);

    return ref.read(reportsRepositoryProvider).getTopProducts(
          companyId: companyId,
          period: period,
          productNames: productNames,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final topProductsProvider = AsyncNotifierProvider.family<
    TopProductsNotifier, List<TopProduct>, ReportPeriod>(
  TopProductsNotifier.new,
);

// ============================================================================
// Top customers
// ============================================================================

class TopCustomersNotifier
    extends FamilyAsyncNotifier<List<TopCustomer>, ReportPeriod> {
  @override
  Future<List<TopCustomer>> build(ReportPeriod period) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return const <TopCustomer>[];
    }

    final List<Customer> customers =
        ref.watch(customersProvider).value ?? const <Customer>[];
    final Map<String, String> customerNames = <String, String>{
      for (final Customer c in customers) c.id: c.name,
    };

    return ref.read(reportsRepositoryProvider).getTopCustomers(
          companyId: companyId,
          period: period,
          customerNames: customerNames,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final topCustomersProvider = AsyncNotifierProvider.family<
    TopCustomersNotifier, List<TopCustomer>, ReportPeriod>(
  TopCustomersNotifier.new,
);

// ============================================================================
// Sales by cashier
// ============================================================================

class SalesByCashierNotifier
    extends FamilyAsyncNotifier<List<CashierSales>, ReportPeriod> {
  @override
  Future<List<CashierSales>> build(ReportPeriod period) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return const <CashierSales>[];
    }

    return ref.read(reportsRepositoryProvider).getSalesByCashier(
          companyId: companyId,
          period: period,
          cashierNames: const <String, String>{},
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final salesByCashierProvider = AsyncNotifierProvider.family<
    SalesByCashierNotifier, List<CashierSales>, ReportPeriod>(
  SalesByCashierNotifier.new,
);

// ============================================================================
// Stock valuation
// ============================================================================

/// Current stock valuation for the selected company (and current branch,
/// when one is selected).
///
/// This is a *state* report, not a time-window report: no [ReportPeriod] is
/// involved.
class StockValuationNotifier extends AsyncNotifier<StockValuationReport> {
  @override
  Future<StockValuationReport> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return StockValuationReport.empty();
    }
    final String? branchId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentBranch?.id,
      ),
    );

    final Map<String, String> productNames = _buildProductNames(ref);
    final Map<String, String> unitNames = _buildUnitNamesByProduct(ref);

    return ref.read(reportsRepositoryProvider).getStockValuation(
          companyId: companyId,
          branchId: branchId,
          productNames: productNames,
          unitNames: unitNames,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final stockValuationProvider =
    AsyncNotifierProvider<StockValuationNotifier, StockValuationReport>(
  StockValuationNotifier.new,
);

// ============================================================================
// Low stock
// ============================================================================

/// Current list of products whose on-hand stock is at or below their
/// configured minimum.
class LowStockNotifier extends AsyncNotifier<List<LowStockItem>> {
  @override
  Future<List<LowStockItem>> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return const <LowStockItem>[];
    }
    final String? branchId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentBranch?.id,
      ),
    );

    final Map<String, String> productNames = _buildProductNames(ref);
    final Map<String, String> unitNames = _buildUnitNamesByProduct(ref);

    return ref.read(reportsRepositoryProvider).getLowStockItems(
          companyId: companyId,
          branchId: branchId,
          productNames: productNames,
          unitNames: unitNames,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final lowStockProvider =
    AsyncNotifierProvider<LowStockNotifier, List<LowStockItem>>(
  LowStockNotifier.new,
);

// ============================================================================
// Dead stock
// ============================================================================

/// Products with stock on hand that have not sold within [DeadStockWindow].
class DeadStockNotifier
    extends FamilyAsyncNotifier<List<DeadStockItem>, DeadStockWindow> {
  @override
  Future<List<DeadStockItem>> build(DeadStockWindow window) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return const <DeadStockItem>[];
    }
    final String? branchId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentBranch?.id,
      ),
    );

    final Map<String, String> productNames = _buildProductNames(ref);
    final Map<String, String> unitNames = _buildUnitNamesByProduct(ref);

    return ref.read(reportsRepositoryProvider).getDeadStockItems(
          companyId: companyId,
          branchId: branchId,
          window: window,
          productNames: productNames,
          unitNames: unitNames,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final deadStockProvider = AsyncNotifierProvider.family<
    DeadStockNotifier, List<DeadStockItem>, DeadStockWindow>(
  DeadStockNotifier.new,
);

// ============================================================================
// Currently selected period (per page)
// ============================================================================

/// Notifier holding the period selected on a single report page.
///
/// Each page keeps its own instance via `autoDispose`, so navigating between
/// pages does not leak the period into unrelated screens. The default is
/// "this month".
class ReportPagePeriodNotifier extends Notifier<ReportPeriod> {
  @override
  ReportPeriod build() => const ReportPeriod(
        type: ReportPeriodType.thisMonth,
      );

  void setPeriod(ReportPeriod period) {
    state = period;
  }
}

final reportPagePeriodProvider = NotifierProvider<
    ReportPagePeriodNotifier, ReportPeriod>(
  ReportPagePeriodNotifier.new,
);

// ============================================================================
// Currently selected dead-stock window (per page)
// ============================================================================

/// Notifier holding the dead-stock lookback window on the report page.
class DeadStockWindowNotifier extends Notifier<DeadStockWindow> {
  @override
  DeadStockWindow build() => DeadStockWindow.days90;

  void setWindow(DeadStockWindow window) {
    state = window;
  }
}

final deadStockWindowProvider = NotifierProvider<
    DeadStockWindowNotifier, DeadStockWindow>(
  DeadStockWindowNotifier.new,
);
