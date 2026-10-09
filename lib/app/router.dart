// lib/app/router.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/companies/presentation/pages/branch_form_page.dart';
import '../features/companies/presentation/pages/branches_page.dart';
import '../features/companies/presentation/pages/company_profile_page.dart';
import '../features/companies/presentation/pages/member_permissions_page.dart';
import '../features/companies/presentation/pages/members_page.dart';
import '../features/home/presentation/pages/home_page.dart';
import '../features/inventory/presentation/pages/inventory_page.dart';
import '../features/inventory/presentation/pages/stock_movements_page.dart';
import '../features/pos/presentation/pages/pos_page.dart';
import '../features/pos/presentation/pages/printer_settings_page.dart';
import '../features/products/presentation/pages/categories_page.dart';
import '../features/products/presentation/pages/products_page.dart';
import '../features/products/presentation/pages/units_page.dart';
import '../features/purchases/presentation/pages/purchase_detail_page.dart';
import '../features/purchases/presentation/pages/purchase_form_page.dart';
import '../features/purchases/presentation/pages/purchases_page.dart';
import '../features/reports/presentation/pages/cashier_report_page.dart';
import '../features/reports/presentation/pages/customer_aging_page.dart';
import '../features/reports/presentation/pages/dead_stock_page.dart';
import '../features/reports/presentation/pages/low_stock_page.dart';
import '../features/reports/presentation/pages/payables_page.dart';
import '../features/reports/presentation/pages/profit_loss_page.dart';
import '../features/reports/presentation/pages/receivables_page.dart';
import '../features/reports/presentation/pages/reports_hub_page.dart';
import '../features/reports/presentation/pages/sales_summary_page.dart';
import '../features/reports/presentation/pages/stock_valuation_page.dart';
import '../features/reports/presentation/pages/supplier_aging_page.dart';
import '../features/reports/presentation/pages/top_customers_page.dart';
import '../features/reports/presentation/pages/top_products_page.dart';
import '../features/sales/presentation/pages/customers_page.dart';
import '../features/sales/presentation/pages/returns_page.dart';
import '../features/sales/presentation/pages/sale_detail_page.dart';
import '../features/sales/presentation/pages/sale_form_page.dart';
import '../features/sales/presentation/pages/sales_page.dart';
import '../features/settings/presentation/pages/company_settings_page.dart';
import '../features/settings/presentation/pages/profile_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/suppliers/presentation/pages/suppliers_page.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/app_error.dart';
import '../shared/widgets/app_loader.dart';

/// Route paths and names used across the application.
abstract final class AppRouter {
  static const String homePath = '/';
  static const String homeName = 'home';

  static const String loginPath = '/login';
  static const String loginName = 'login';

  static const String loadingPath = '/loading';
  static const String loadingName = 'loading';

  static const String productsPath = '/products';
  static const String productsName = 'products';

  static const String categoriesPath = '/products/categories';
  static const String categoriesName = 'categories';

  static const String unitsPath = '/products/units';
  static const String unitsName = 'units';

  static const String inventoryPath = '/inventory';
  static const String inventoryName = 'inventory';

  static const String stockMovementsPath = '/inventory/movements';
  static const String stockMovementsName = 'stock-movements';

  static const String suppliersPath = '/suppliers';
  static const String suppliersName = 'suppliers';

  static const String purchasesPath = '/purchases';
  static const String purchasesName = 'purchases';

  static const String purchaseNewPath = '/purchases/new';
  static const String purchaseNewName = 'purchase-new';

  static const String purchaseDetailPath = '/purchases/:id';
  static const String purchaseDetailName = 'purchase-detail';

  static const String purchaseEditPath = '/purchases/:id/edit';
  static const String purchaseEditName = 'purchase-edit';

  static const String customersPath = '/customers';
  static const String customersName = 'customers';

  static const String salesPath = '/sales';
  static const String salesName = 'sales';

  static const String saleNewPath = '/sales/new';
  static const String saleNewName = 'sale-new';

  static const String saleDetailPath = '/sales/:id';
  static const String saleDetailName = 'sale-detail';

  static const String saleEditPath = '/sales/:id/edit';
  static const String saleEditName = 'sale-edit';

  static const String returnsPath = '/returns';
  static const String returnsName = 'returns';

  static const String settingsPath = '/settings';
  static const String settingsName = 'settings';

  static const String companySettingsPath = '/settings/company';
  static const String companySettingsName = 'company-settings';

  static const String companyProfilePath = '/settings/company-profile';
  static const String companyProfileName = 'company-profile';

  static const String branchesPath = '/settings/branches';
  static const String branchesName = 'branches';

  static const String branchNewPath = '/settings/branches/new';
  static const String branchNewName = 'branch-new';

  static const String branchEditPath = '/settings/branches/:id/edit';
  static const String branchEditName = 'branch-edit';

  static const String membersPath = '/settings/members';
  static const String membersName = 'members';

  static const String memberPermissionsPath =
      '/settings/members/:id/permissions';
  static const String memberPermissionsName = 'member-permissions';

  static const String profilePath = '/settings/profile';
  static const String profileName = 'profile';

  static const String printerSettingsPath = '/settings/printer';
  static const String printerSettingsName = 'printer-settings';

  // ---- Phase 9: Reports ----
  static const String reportsPath = '/reports';
  static const String reportsName = 'reports';

  static const String reportSalesSummaryPath = '/reports/sales-summary';
  static const String reportSalesSummaryName = 'report-sales-summary';

  static const String reportCashierPath = '/reports/cashier';
  static const String reportCashierName = 'report-cashier';

  static const String reportTopProductsPath = '/reports/top-products';
  static const String reportTopProductsName = 'report-top-products';

  static const String reportTopCustomersPath = '/reports/top-customers';
  static const String reportTopCustomersName = 'report-top-customers';

  static const String reportStockValuationPath = '/reports/stock-valuation';
  static const String reportStockValuationName = 'report-stock-valuation';

  static const String reportLowStockPath = '/reports/low-stock';
  static const String reportLowStockName = 'report-low-stock';

  static const String reportDeadStockPath = '/reports/dead-stock';
  static const String reportDeadStockName = 'report-dead-stock';

  static const String reportProfitLossPath = '/reports/profit-loss';
  static const String reportProfitLossName = 'report-profit-loss';

  static const String reportReceivablesPath = '/reports/receivables';
  static const String reportReceivablesName = 'report-receivables';

  static const String reportCustomerAgingPath = '/reports/customer-aging';
  static const String reportCustomerAgingName = 'report-customer-aging';

  static const String reportSupplierAgingPath = '/reports/supplier-aging';
  static const String reportSupplierAgingName = 'report-supplier-aging';

  static const String reportPayablesPath = '/reports/payables';
  static const String reportPayablesName = 'report-payables';

  static const String posPath = '/pos';
  static const String posName = 'pos';
}

/// Provides the application router.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final GoRouter router = GoRouter(
    initialLocation: AppRouter.homePath,
    redirect: (BuildContext context, GoRouterState state) {
      final AuthState auth = ref.read(authProvider);
      final String location = state.matchedLocation;

      if (auth.isUnknown) {
        return location == AppRouter.loadingPath ? null : AppRouter.loadingPath;
      }

      if (auth.isUnauthenticated) {
        return location == AppRouter.loginPath ? null : AppRouter.loginPath;
      }

      if (location == AppRouter.loginPath ||
          location == AppRouter.loadingPath) {
        return AppRouter.homePath;
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRouter.homePath,
        name: AppRouter.homeName,
        builder: (BuildContext context, GoRouterState state) =>
            const HomePage(),
      ),
      GoRoute(
        path: AppRouter.loginPath,
        name: AppRouter.loginName,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),
      GoRoute(
        path: AppRouter.loadingPath,
        name: AppRouter.loadingName,
        builder: (BuildContext context, GoRouterState state) =>
            const _AuthLoadingPage(),
      ),
      GoRoute(
        path: AppRouter.productsPath,
        name: AppRouter.productsName,
        builder: (BuildContext context, GoRouterState state) =>
            const ProductsPage(),
      ),
      GoRoute(
        path: AppRouter.categoriesPath,
        name: AppRouter.categoriesName,
        builder: (BuildContext context, GoRouterState state) =>
            const CategoriesPage(),
      ),
      GoRoute(
        path: AppRouter.unitsPath,
        name: AppRouter.unitsName,
        builder: (BuildContext context, GoRouterState state) =>
            const UnitsPage(),
      ),
      GoRoute(
        path: AppRouter.inventoryPath,
        name: AppRouter.inventoryName,
        builder: (BuildContext context, GoRouterState state) =>
            const InventoryPage(),
      ),
      GoRoute(
        path: AppRouter.stockMovementsPath,
        name: AppRouter.stockMovementsName,
        builder: (BuildContext context, GoRouterState state) =>
            const StockMovementsPage(),
      ),
      GoRoute(
        path: AppRouter.suppliersPath,
        name: AppRouter.suppliersName,
        builder: (BuildContext context, GoRouterState state) =>
            const SuppliersPage(),
      ),
      GoRoute(
        path: AppRouter.purchasesPath,
        name: AppRouter.purchasesName,
        builder: (BuildContext context, GoRouterState state) =>
            const PurchasesPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            name: AppRouter.purchaseNewName,
            builder: (BuildContext context, GoRouterState state) =>
                const PurchaseFormPage(),
          ),
          GoRoute(
            path: ':id',
            name: AppRouter.purchaseDetailName,
            builder: (BuildContext context, GoRouterState state) {
              final String? id = state.pathParameters['id'];
              return PurchaseDetailPage(key: ValueKey<String>(id ?? ''));
            },
            routes: <RouteBase>[
              GoRoute(
                path: 'edit',
                name: AppRouter.purchaseEditName,
                builder: (BuildContext context, GoRouterState state) {
                  final String? id = state.pathParameters['id'];
                  return PurchaseFormPage(
                    key: ValueKey<String>('edit-${id ?? ''}'),
                    purchaseId: id,
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRouter.customersPath,
        name: AppRouter.customersName,
        builder: (BuildContext context, GoRouterState state) =>
            const CustomersPage(),
      ),
      GoRoute(
        path: AppRouter.salesPath,
        name: AppRouter.salesName,
        builder: (BuildContext context, GoRouterState state) =>
            const SalesPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            name: AppRouter.saleNewName,
            builder: (BuildContext context, GoRouterState state) =>
                const SaleFormPage(),
          ),
          GoRoute(
            path: ':id',
            name: AppRouter.saleDetailName,
            builder: (BuildContext context, GoRouterState state) {
              final String? id = state.pathParameters['id'];
              return SaleDetailPage(
                key: ValueKey<String>('sale-detail-${id ?? ''}'),
                saleId: id ?? '',
              );
            },
            routes: <RouteBase>[
              GoRoute(
                path: 'edit',
                name: AppRouter.saleEditName,
                builder: (BuildContext context, GoRouterState state) {
                  final String? id = state.pathParameters['id'];
                  return SaleFormPage(
                    key: ValueKey<String>('sale-edit-${id ?? ''}'),
                    saleId: id,
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRouter.returnsPath,
        name: AppRouter.returnsName,
        builder: (BuildContext context, GoRouterState state) =>
            const ReturnsPage(),
      ),
      GoRoute(
        path: AppRouter.settingsPath,
        name: AppRouter.settingsName,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'company',
            name: AppRouter.companySettingsName,
            builder: (BuildContext context, GoRouterState state) =>
                const CompanySettingsPage(),
          ),
          GoRoute(
            path: 'company-profile',
            name: AppRouter.companyProfileName,
            builder: (BuildContext context, GoRouterState state) =>
                const CompanyProfilePage(),
          ),
          GoRoute(
            path: 'branches',
            name: AppRouter.branchesName,
            builder: (BuildContext context, GoRouterState state) =>
                const BranchesPage(),
            routes: <RouteBase>[
              GoRoute(
                path: 'new',
                name: AppRouter.branchNewName,
                builder: (BuildContext context, GoRouterState state) =>
                    const BranchFormPage(),
              ),
              GoRoute(
                path: ':id/edit',
                name: AppRouter.branchEditName,
                builder: (BuildContext context, GoRouterState state) {
                  final String? id = state.pathParameters['id'];
                  return BranchFormPage(
                    key: ValueKey<String>('branch-edit-${id ?? ''}'),
                    branchId: id,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: 'members',
            name: AppRouter.membersName,
            builder: (BuildContext context, GoRouterState state) =>
                const MembersPage(),
            routes: <RouteBase>[
              GoRoute(
                path: ':id/permissions',
                name: AppRouter.memberPermissionsName,
                builder: (BuildContext context, GoRouterState state) {
                  final String? id = state.pathParameters['id'];
                  return MemberPermissionsPage(
                    key: ValueKey<String>('member-perm-${id ?? ''}'),
                    memberId: id ?? '',
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: 'profile',
            name: AppRouter.profileName,
            builder: (BuildContext context, GoRouterState state) =>
                const ProfilePage(),
          ),
          GoRoute(
            path: 'printer',
            name: AppRouter.printerSettingsName,
            builder: (BuildContext context, GoRouterState state) =>
                const PrinterSettingsPage(),
          ),
        ],
      ),
      // ---- Phase 9: Reports ----
      GoRoute(
        path: AppRouter.reportsPath,
        name: AppRouter.reportsName,
        builder: (BuildContext context, GoRouterState state) =>
            const ReportsHubPage(),
      ),
      GoRoute(
        path: AppRouter.reportSalesSummaryPath,
        name: AppRouter.reportSalesSummaryName,
        builder: (BuildContext context, GoRouterState state) =>
            const SalesSummaryPage(),
      ),
      GoRoute(
        path: AppRouter.reportCashierPath,
        name: AppRouter.reportCashierName,
        builder: (BuildContext context, GoRouterState state) =>
            const CashierReportPage(),
      ),
      GoRoute(
        path: AppRouter.reportTopProductsPath,
        name: AppRouter.reportTopProductsName,
        builder: (BuildContext context, GoRouterState state) =>
            const TopProductsPage(),
      ),
      GoRoute(
        path: AppRouter.reportTopCustomersPath,
        name: AppRouter.reportTopCustomersName,
        builder: (BuildContext context, GoRouterState state) =>
            const TopCustomersPage(),
      ),
      GoRoute(
        path: AppRouter.reportStockValuationPath,
        name: AppRouter.reportStockValuationName,
        builder: (BuildContext context, GoRouterState state) =>
            const StockValuationPage(),
      ),
      GoRoute(
        path: AppRouter.reportLowStockPath,
        name: AppRouter.reportLowStockName,
        builder: (BuildContext context, GoRouterState state) =>
            const LowStockPage(),
      ),
      GoRoute(
        path: AppRouter.reportDeadStockPath,
        name: AppRouter.reportDeadStockName,
        builder: (BuildContext context, GoRouterState state) =>
            const DeadStockPage(),
      ),
      GoRoute(
        path: AppRouter.reportProfitLossPath,
        name: AppRouter.reportProfitLossName,
        builder: (BuildContext context, GoRouterState state) =>
            const ProfitLossPage(),
      ),
      GoRoute(
        path: AppRouter.reportReceivablesPath,
        name: AppRouter.reportReceivablesName,
        builder: (BuildContext context, GoRouterState state) =>
            const ReceivablesPage(),
      ),
      GoRoute(
        path: AppRouter.reportCustomerAgingPath,
        name: AppRouter.reportCustomerAgingName,
        builder: (BuildContext context, GoRouterState state) =>
            const CustomerAgingPage(),
      ),
      GoRoute(
        path: AppRouter.reportSupplierAgingPath,
        name: AppRouter.reportSupplierAgingName,
        builder: (BuildContext context, GoRouterState state) =>
            const SupplierAgingPage(),
      ),
      GoRoute(
        path: AppRouter.reportPayablesPath,
        name: AppRouter.reportPayablesName,
        builder: (BuildContext context, GoRouterState state) =>
            const PayablesPage(),
      ),
      GoRoute(
        path: AppRouter.posPath,
        name: AppRouter.posName,
        builder: (BuildContext context, GoRouterState state) =>
            const PosPage(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return Scaffold(
        body: AppErrorView(
          title: l10n.errorTitle,
          message: l10n.errorRouteNotFound,
          retryLabel: l10n.actionGoHome,
          onRetry: () => context.goNamed(AppRouter.homeName),
        ),
      );
    },
  );

  ref.listen<AuthState>(authProvider, (AuthState? previous, AuthState next) {
    if (previous?.status != next.status) {
      router.refresh();
    }
  });

  ref.onDispose(router.dispose);

  return router;
});

/// Minimal loading screen shown while session restoration is in flight.
class _AuthLoadingPage extends StatelessWidget {
  const _AuthLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: AppLoader());
  }
}
