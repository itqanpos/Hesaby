// lib/features/reports/presentation/providers/reports_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../data/datasources/reports_remote_datasource.dart';
import '../../data/repositories/reports_repository_impl.dart';
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
// Helpers
// ============================================================================

/// Reads the currently selected company id, throwing when none is selected.
///
/// Reports are only meaningful with a company; the page-level providers
/// translate this exception into an error state.
String _requireCompanyId(Ref ref) {
  final CompanyContextState context = ref.read(companyContextProvider);
  final String? id = context.currentCompany?.id;
  if (id == null) {
    throw const ReportException(
      type: ReportFailureType.unauthorized,
      cause: 'No company is currently selected.',
    );
  }
  return id;
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
      // Return an empty summary rather than throwing: the UI can render a
      // meaningful zero-state when no company is selected.
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

/// Top products by revenue for the currently selected company over [period].
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

    // Load the products catalogue once; use it both as a lookup table for
    // display names and (indirectly) to keep the aggregation stable while
    // the network fetch is in flight.
    final List<Product> products =
        ref.watch(productsProvider).value ?? const <Product>[];
    final Map<String, String> productNames = <String, String>{
      for (final Product p in products) p.id: p.name,
    };

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

/// Top customers by spending for the currently selected company over
/// [period].
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

/// Sales grouped by cashier for the currently selected company over
/// [period].
///
/// Cashier names are not yet available from a dedicated table, so an empty
/// map is passed: the repository falls back to a short id suffix.
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
