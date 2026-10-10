// lib/features/sales/presentation/pages/sales_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/invalidation/data_invalidation.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../dialogs/sales_filter_sheet.dart';
import '../providers/sales_providers.dart';
import '../widgets/sales_kpi_row.dart';

/// Sales list page.
class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  SalesFilter _filter = const SalesFilter();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _filter.isNotEmpty || _searchQuery.trim().isNotEmpty;

  Future<void> _openFilterSheet() async {
    final SalesFilter? result = await showSalesFilterSheet(
      context: context,
      current: _filter,
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() => _filter = result);
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filter = const SalesFilter();
    });
  }

  /// Pull-to-refresh: reuse the same invalidation surface as post-write so
  /// the manual and automatic paths converge on identical state.
  Future<void> _refresh() async {
    DataInvalidation.afterSale(ref);
    await Future.wait(<Future<void>>[
      ref.refresh(salesProvider.future),
      ref.refresh(customersProvider.future),
    ]);
  }

  bool _matches(Sale sale, Map<String, String> customerNames) {
    if (_filter.status != null && sale.status != _filter.status) {
      return false;
    }
    if (_filter.payment != null && sale.paymentStatus != _filter.payment) {
      return false;
    }

    final DateTime localDate = sale.saleDate.toLocal();
    final DateTime? fromDate = _filter.fromDate;
    final DateTime? toDate = _filter.toDate;
    if (fromDate != null && localDate.isBefore(fromDate)) {
      return false;
    }
    if (toDate != null && localDate.isAfter(toDate)) {
      return false;
    }

    final String trimmed = _searchQuery.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return true;
    }

    final String invoice = (sale.invoiceNumber ?? '').toLowerCase();
    if (invoice.contains(trimmed)) {
      return true;
    }

    final String? customerId = sale.customerId;
    if (customerId != null) {
      final String name = customerNames[customerId] ?? '';
      if (name.toLowerCase().contains(trimmed)) {
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final CompanyContextState contextState =
        ref.watch(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;

    final AsyncValue<List<Sale>> salesAsync = ref.watch(salesProvider);
    final AsyncValue<List<Customer>> customersAsync =
        ref.watch(customersProvider);

    final bool anyLoading =
        salesAsync.isLoading || customersAsync.isLoading;
    final Object? firstError = salesAsync.error ?? customersAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('فواتير البيع'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: anyLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'إضافة فاتورة',
            onPressed: anyLoading || firstError != null || branchId == null
                ? null
                : () => context.pushNamed(AppRouter.saleNewName),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          if (anyLoading) {
            return const AppLoader();
          }

          if (firstError != null) {
            return AppErrorView(
              title: 'تعذّر تحميل فواتير البيع',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: _refresh,
            );
          }

          if (branchId == null) {
            return const AppEmptyView(
              icon: Icons.store_mall_directory_outlined,
              title: 'لم يتم اختيار فرع',
              message: 'اختر فرعًا من الصفحة الرئيسية لعرض فواتير البيع.',
            );
          }

          final List<Sale> allSales = salesAsync.value ?? const <Sale>[];
          final List<Customer> customers =
              customersAsync.value ?? const <Customer>[];
          final Map<String, String> customerNames = <String, String>{
            for (final Customer c in customers) c.id: c.name,
          };

          final List<Sale> filtered = allSales
              .where((Sale s) => _matches(s, customerNames))
              .toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: SalesKpiRow(sales: allSales),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        controller: _searchController,
                        hint: 'ابحث برقم الفاتورة أو اسم العميل',
                        prefixIcon: Icons.search,
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'مسح البحث',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                        onChanged: (String v) =>
                            setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FilterButton(
                      activeCount: _filter.activeCount,
                      onPressed: _openFilterSheet,
                    ),
                  ],
                ),
              ),

              if (_filter.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ActiveFilterChips(
                    filter: _filter,
                    onClearAll: _clearAllFilters,
                  ),
                ),

              // ---- List (pull-to-refresh enabled) ----
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: Builder(
                    builder: (BuildContext _) {
                      if (allSales.isEmpty) {
                        return _RefreshableMessage(
                          child: AppEmptyView(
                            icon: Icons.point_of_sale_outlined,
                            title: 'لا توجد فواتير بيع',
                            message:
                                'ابدأ بتسجيل أول فاتورة بيع لأحد العملاء.',
                            action: AppButton(
                              label: 'إضافة فاتورة',
                              icon: Icons.add,
                              onPressed: () =>
                                  context.pushNamed(AppRouter.saleNewName),
                            ),
                          ),
                        );
                      }
                      if (filtered.isEmpty) {
                        return _RefreshableMessage(
                          child: AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message:
                                'لم تُطابق أي فاتورة الفلاتر المحددة.',
                            action: _hasActiveFilters
                                ? AppButton(
                                    label: 'مسح الفلاتر',
                                    icon: Icons.filter_alt_off_outlined,
                                    variant: AppButtonVariant.secondary,
                                    onPressed: _clearAllFilters,
                                  )
                                : null,
                          ),
                        );
                      }
                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final Sale sale = filtered[index];
                          return _SaleCard(
                            sale: sale,
                            customerName: _resolveCardCustomerName(
                              customerNames,
                              sale.customerId,
                            ),
                            onTap: () => _openDetail(context, sale),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, Sale sale) async {
    await context.pushNamed(
      AppRouter.saleDetailName,
      pathParameters: <String, String>{'id': sale.id},
    );
  }

  static String _resolveCardCustomerName(
    Map<String, String> customerNames,
    String? customerId,
  ) {
    if (customerId == null) {
      return 'عميل نقدي';
    }
    return customerNames[customerId] ?? 'عميل محذوف';
  }
}

// -----------------------------------------------------------------------------
// Refreshable wrapper for empty / error states.
//
// Wraps a non-scrollable widget in a scroll view sized to fill its parent
// so RefreshIndicator can trigger even when the content is just a message.
// -----------------------------------------------------------------------------

class _RefreshableMessage extends StatelessWidget {
  const _RefreshableMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Filter button
// -----------------------------------------------------------------------------

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isActive = activeCount > 0;

    return Material(
      color: isActive ? scheme.primary : scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.tune,
                size: 20,
                color: isActive ? scheme.onPrimary : scheme.onSurface,
              ),
              if (isActive) ...<Widget>[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$activeCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Active filter chips
// -----------------------------------------------------------------------------

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({
    required this.filter,
    required this.onClearAll,
  });

  final SalesFilter filter;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[];

    if (filter.dateFilter != SalesDateFilter.all) {
      chips.add(_chip(context, _dateLabel()));
    }
    if (filter.status != null) {
      chips.add(_chip(context, _statusLabel(filter.status!)));
    }
    if (filter.payment != null) {
      chips.add(_chip(context, _paymentLabel(filter.payment!)));
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < chips.length; i++) ...<Widget>[
            chips[i],
            if (i < chips.length - 1) const SizedBox(width: 6),
          ],
          const SizedBox(width: 6),
          ActionChip(
            avatar: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('مسح'),
            onPressed: onClearAll,
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  String _dateLabel() {
    switch (filter.dateFilter) {
      case SalesDateFilter.all:
        return 'الكل';
      case SalesDateFilter.today:
        return 'اليوم';
      case SalesDateFilter.thisWeek:
        return 'هذا الأسبوع';
      case SalesDateFilter.thisMonth:
        return 'هذا الشهر';
      case SalesDateFilter.thisYear:
        return 'هذا العام';
      case SalesDateFilter.custom:
        if (filter.customRange != null) {
          final DateFormat fmt = DateFormat('yy/MM/dd');
          return '${fmt.format(filter.customRange!.start)} → '
              '${fmt.format(filter.customRange!.end)}';
        }
        return 'نطاق مخصص';
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case SaleStatus.draft:
        return 'مسودة';
      case SaleStatus.confirmed:
        return 'مؤكدة';
      case SaleStatus.cancelled:
        return 'ملغاة';
      default:
        return status;
    }
  }

  String _paymentLabel(String payment) {
    switch (payment) {
      case PaymentStatus.unpaid:
        return 'غير مدفوع';
      case PaymentStatus.partial:
        return 'مدفوع جزئيًا';
      case PaymentStatus.paid:
        return 'مدفوع';
      default:
        return payment;
    }
  }
}

// -----------------------------------------------------------------------------
// Sale card
// -----------------------------------------------------------------------------

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.customerName,
    required this.onTap,
  });

  final Sale sale;
  final String customerName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final DateFormat dateTimeFormat = DateFormat.yMd('ar_EG').add_Hm();

    final (Color badgeBg, Color badgeFg) = _statusColors(
      scheme,
      sale.status,
    );
    final String statusLabel = _statusLabel(sale.status);

    final String? invoice = sale.invoiceNumber;
    final String headerTitle =
        (invoice != null && invoice.isNotEmpty) ? invoice : 'بدون رقم فاتورة';

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: badgeBg,
                foregroundColor: badgeFg,
                child: const Icon(Icons.point_of_sale_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            headerTitle,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            child: Text(
                              statusLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: badgeFg,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customerName,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Text(
                          dateTimeFormat.format(sale.saleDate.toLocal()),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          moneyFormat.format(sale.total),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (sale.isUnpaid) ...<Widget>[
                          const SizedBox(width: 8),
                          _PaymentBadge(
                            label: 'غير مدفوعة',
                            background: scheme.errorContainer,
                            foreground: scheme.onErrorContainer,
                          ),
                        ] else if (sale.isPartiallyPaid) ...<Widget>[
                          const SizedBox(width: 8),
                          _PaymentBadge(
                            label:
                                'مدفوع جزئيًا (${moneyFormat.format(sale.amountDue)} متبقٍ)',
                            background: scheme.tertiaryContainer,
                            foreground: scheme.onTertiaryContainer,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
              ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Localization helpers
// -----------------------------------------------------------------------------

String _statusLabel(String status) {
  switch (status) {
    case SaleStatus.draft:
      return 'مسودة';
    case SaleStatus.confirmed:
      return 'مؤكدة';
    case SaleStatus.cancelled:
      return 'ملغاة';
    default:
      return 'غير معروفة';
  }
}

(Color background, Color foreground) _statusColors(
  ColorScheme scheme,
  String status,
) {
  switch (status) {
    case SaleStatus.draft:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    case SaleStatus.confirmed:
      return (scheme.primaryContainer, scheme.onPrimaryContainer);
    case SaleStatus.cancelled:
      return (scheme.errorContainer, scheme.onErrorContainer);
    default:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
  }
}

String _errorMessage(Object error) {
  if (error is SaleException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(SalesFailureType type) => switch (type) {
      SalesFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      SalesFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      SalesFailureType.notFound =>
        'الفاتورة المطلوبة غير موجودة أو تم حذفها.',
      SalesFailureType.invalidStatusTransition =>
        'لا يمكن إجراء هذه العملية على الفاتورة في حالتها الحالية.',
      SalesFailureType.emptySale =>
        'لا يمكن تأكيد فاتورة بدون بنود. أضف منتجًا واحدًا على الأقل.',
      SalesFailureType.invoiceNumberConflict =>
        'يوجد فاتورة أخرى بنفس الرقم في هذه الشركة.',
      SalesFailureType.customerNotFound =>
        'العميل المختار غير متاح. يرجى إعادة اختياره.',
      SalesFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      SalesFailureType.productNotFound =>
        'أحد المنتجات المختارة غير متاح.',
      SalesFailureType.unitNotFound =>
        'إحدى الوحدات المختارة غير متاحة.',
      SalesFailureType.insufficientStock =>
        'الرصيد غير كافٍ. لا يمكن إتمام الفاتورة.',
      SalesFailureType.invalidPayment =>
        'المبلغ المدفوع أكبر من إجمالي الفاتورة.',
      SalesFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الفواتير. يرجى المحاولة لاحقًا.',
      SalesFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };
