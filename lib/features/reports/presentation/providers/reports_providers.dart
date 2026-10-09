// lib/features/reports/presentation/providers/reports_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../../settings/domain/entities/user_profile.dart';
import '../../../settings/presentation/providers/user_profile_providers.dart';
import '../../../suppliers/domain/entities/supplier.dart';
import '../../../suppliers/presentation/providers/supplier_providers.dart';
import '../../data/datasources/reports_remote_datasource.dart';
import '../../data/repositories/reports_repository_impl.dart';
import '../../domain/entities/aging_reports.dart';
import '../../domain/entities/financial_reports.dart';
import '../../domain/entities/inventory_reports.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/sales_reports.dart';
import '../../domain/repositories/reports_repository.dart';

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

Map<String, String> _buildProductNames(Ref ref) {
  final List<Product> products =
      ref.watch(productsProvider).value ?? const <Product>[];
  return <String, String>{
    for (final Product p in products) p.id: p.name,
  };
}

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
    final String name = unitNameById[p.defaultUnitId] ?? '';
    if (name.isNotEmpty) {
      result[p.id] = name;
    }
  }
  return result;
}

// ============================================================================
// Sales summary
// ============================================================================

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
    return ref.read(reportsRepositoryProvider).getTopProducts(
          companyId: companyId,
          period: period,
          productNames: _buildProductNames(ref),
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
    final Map<String, String> cashierNames = <String, String>{};
    final String? currentUserId = ref.watch(
      authProvider.select((AuthState s) => s.session?.userId),
    );
    final String? currentUserName = ref.watch(
      userProfileProvider.select(
        (AsyncValue<UserProfile?> v) => v.valueOrNull?.fullName,
      ),
    );
    if (currentUserId != null &&
        currentUserName != null &&
        currentUserName.trim().isNotEmpty) {
      cashierNames[currentUserId] = currentUserName.trim();
    }
    return ref.read(reportsRepositoryProvider).getSalesByCashier(
          companyId: companyId,
          period: period,
          cashierNames: cashierNames,
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
    return ref.read(reportsRepositoryProvider).getStockValuation(
          companyId: companyId,
          branchId: branchId,
          productNames: _buildProductNames(ref),
          unitNames: _buildUnitNamesByProduct(ref),
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
    return ref.read(reportsRepositoryProvider).getLowStockItems(
          companyId: companyId,
          branchId: branchId,
          productNames: _buildProductNames(ref),
          unitNames: _buildUnitNamesByProduct(ref),
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
    return ref.read(reportsRepositoryProvider).getDeadStockItems(
          companyId: companyId,
          branchId: branchId,
          window: window,
          productNames: _buildProductNames(ref),
          unitNames: _buildUnitNamesByProduct(ref),
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
// Profit & Loss
// ============================================================================

class ProfitLossNotifier
    extends FamilyAsyncNotifier<ProfitLossSummary, ReportPeriod> {
  @override
  Future<ProfitLossSummary> build(ReportPeriod period) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return ProfitLossSummary.empty(period);
    }
    return ref.read(reportsRepositoryProvider).getProfitLoss(
          companyId: companyId,
          period: period,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final profitLossProvider = AsyncNotifierProvider.family<
    ProfitLossNotifier, ProfitLossSummary, ReportPeriod>(
  ProfitLossNotifier.new,
);

// ============================================================================
// Receivables
// ============================================================================

class ReceivablesNotifier extends AsyncNotifier<ReceivablesReport> {
  @override
  Future<ReceivablesReport> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return ReceivablesReport.empty();
    }
    return ref.read(reportsRepositoryProvider).getReceivables(
          companyId: companyId,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final receivablesProvider =
    AsyncNotifierProvider<ReceivablesNotifier, ReceivablesReport>(
  ReceivablesNotifier.new,
);

// ============================================================================
// Payables
// ============================================================================

class PayablesNotifier
    extends FamilyAsyncNotifier<PayablesReport, ReportPeriod> {
  @override
  Future<PayablesReport> build(ReportPeriod period) async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return PayablesReport.empty(period);
    }
    final List<Supplier> suppliers =
        ref.watch(suppliersProvider).value ?? const <Supplier>[];
    final Map<String, String> supplierNames = <String, String>{
      for (final Supplier s in suppliers) s.id: s.name,
    };
    return ref.read(reportsRepositoryProvider).getPayables(
          companyId: companyId,
          period: period,
          supplierNames: supplierNames,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final payablesProvider = AsyncNotifierProvider.family<
    PayablesNotifier, PayablesReport, ReportPeriod>(
  PayablesNotifier.new,
);

// ============================================================================
// Customer aging
// ============================================================================

class CustomerAgingNotifier extends AsyncNotifier<AgingReport> {
  @override
  Future<AgingReport> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return AgingReport.empty();
    }
    return ref.read(reportsRepositoryProvider).getCustomerAging(
          companyId: companyId,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final customerAgingProvider =
    AsyncNotifierProvider<CustomerAgingNotifier, AgingReport>(
  CustomerAgingNotifier.new,
);

// ============================================================================
// Supplier aging
// ============================================================================

class SupplierAgingNotifier extends AsyncNotifier<SupplierAgingReport> {
  @override
  Future<SupplierAgingReport> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    if (companyId == null) {
      return SupplierAgingReport.empty();
    }
    return ref.read(reportsRepositoryProvider).getSupplierAging(
          companyId: companyId,
        );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final supplierAgingProvider =
    AsyncNotifierProvider<SupplierAgingNotifier, SupplierAgingReport>(
  SupplierAgingNotifier.new,
);

// ============================================================================
// Per-page period / window
// ============================================================================

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
