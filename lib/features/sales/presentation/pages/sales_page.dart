// lib/features/sales/presentation/pages/sales_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
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
import '../providers/sales_providers.dart';
import '../widgets/sales_kpi_row.dart';

/// Date presets exposed as chips above the sales list.
enum _SalesDateFilter {
  all,
  today,
  thisWeek,
  thisMonth,
  thisYear,
  custom,
}

/// Sales list page.
///
/// Displays the sales invoices of the currently selected company, with
/// client-side filters on date, status, payment status and a free-text
/// search across invoice number and customer name. Tapping a card pushes
/// the dedicated `SaleDetailPage` route.
class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// `null` means "all statuses".
  String? _statusFilter;

  /// `null` means "all payment states".
  String? _paymentFilter;

  _SalesDateFilter _dateFilter = _SalesDateFilter.all;
  DateTimeRange? _customDateRange;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Filter state helpers
  // ---------------------------------------------------------------------------

  bool get _hasActiveFilters {
    return _searchQuery.trim().isNotEmpty ||
        _statusFilter != null ||
        _paymentFilter != null ||
        _dateFilter != _SalesDateFilter.all;
  }

  DateTime? _computeFromDate() {
    final DateTime now = DateTime.now();
    switch (_dateFilter) {
      case _SalesDateFilter.all:
        return null;
      case _SalesDateFilter.today:
        return DateTime(now.year, now.month, now.day);
      case _SalesDateFilter.thisWeek:
        // ISO 8601: Monday is the first day of the week (`weekday == 1`).
        return DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
      case _SalesDateFilter.thisMonth:
        return DateTime(now.year, now.month, 1);
      case _SalesDateFilter.thisYear:
        return DateTime(now.year, 1, 1);
      case _SalesDateFilter.custom:
        final DateTime? start = _customDateRange?.start;
        if (start == null) {
          return null;
        }
        return DateTime(start.year, start.month, start.day);
    }
  }

  DateTime? _computeToDate() {
    final DateTime now = DateTime.now();
    switch (_dateFilter) {
      case _SalesDateFilter.all:
        return null;
      case _SalesDateFilter.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case _SalesDateFilter.thisWeek:
      case _SalesDateFilter.thisMonth:
      case _SalesDateFilter.thisYear:
        return now;
      case _SalesDateFilter.custom:
        final DateTime? end = _customDateRange?.end;
        if (end == null) {
          return null;
        }
        return DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    }
  }

  // ---------------------------------------------------------------------------
  // Filter actions
  // ---------------------------------------------------------------------------

  Future<void> _selectDateFilter(_SalesDateFilter next) async {
    if (next != _SalesDateFilter.custom) {
      setState(() {
        _dateFilter = next;
        _customDateRange = null;
      });
      return;
    }

    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _customDateRange,
      helpText: 'اختر الفترة',
      saveText: 'تطبيق',
    );

    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _dateFilter = _SalesDateFilter.custom;
      _customDateRange = picked;
    });
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _statusFilter = null;
      _paymentFilter = null;
      _dateFilter = _SalesDateFilter.all;
      _customDateRange = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------------

  bool _matchesFilters(Sale sale, Map<String, String> customerNames) {
    // 1) Status
    if (_statusFilter != null && sale.status != _statusFilter) {
      return false;
    }

    // 2) Payment status
    if (_paymentFilter != null && sale.paymentStatus != _paymentFilter) {
      return false;
    }

    // 3) Date window (inclusive)
    final DateTime localDate = sale.saleDate.toLocal();
    final DateTime? fromDate = _computeFromDate();
    final DateTime? toDate = _computeToDate();
    if (fromDate != null && localDate.isBefore(fromDate)) {
      return false;
    }
    if (toDate != null && localDate.isAfter(toDate)) {
      return false;
    }

    // 4) Free-text search: invoice number OR customer name
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
              onRetry: () {
                ref.invalidate(salesProvider);
                ref.invalidate(customersProvider);
              },
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
            for (final Customer customer in customers)
              customer.id: customer.name,
          };

          final List<Sale> filtered = allSales
              .where((Sale s) => _matchesFilters(s, customerNames))
              .toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- KPI overview (unaffected by filters) ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: SalesKpiRow(sales: allSales),
              ),

              // ---- Search field ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
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
                  onChanged: (String value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),

              // ---- Date filter chips ----
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DateFilterChips(
                  selected: _dateFilter,
                  customRange: _customDateRange,
                  onChanged: _selectDateFilter,
                ),
              ),

              // ---- Status filter chips ----
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _StatusFilterChips(
                  selected: _statusFilter,
                  onChanged: (String? status) {
                    setState(() => _statusFilter = status);
                  },
                ),
              ),

              // ---- Payment filter chips ----
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PaymentFilterChips(
                  selected: _paymentFilter,
                  onChanged: (String? payment) {
                    setState(() => _paymentFilter = payment);
                  },
                ),
              ),

              // ---- Clear all filters ----
              if (_hasActiveFilters)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ActionChip(
                      avatar: const Icon(Icons.filter_alt_off_outlined,
                          size: 16),
                      label: const Text('مسح الفلاتر'),
                      onPressed: _clearAllFilters,
                    ),
                  ),
                ),

              // ---- List ----
              Expanded(
                child: allSales.isEmpty
                    ? AppEmptyView(
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
                      )
                    : filtered.isEmpty
                        ? AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message: 'لم تُطابق أي فاتورة الفلاتر المحددة.',
                            action: _hasActiveFilters
                                ? AppButton(
                                    label: 'مسح الفلاتر',
                                    icon: Icons.filter_alt_off_outlined,
                                    variant: AppButtonVariant.secondary,
                                    onPressed: _clearAllFilters,
                                  )
                                : null,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder:
                                (BuildContext context, int index) {
                              final Sale sale = filtered[index];
                              final String customerName =
                                  _resolveCardCustomerName(
                                customerNames,
                                sale.customerId,
                              );
                              return _SaleCard(
                                sale: sale,
                                customerName: customerName,
                                onTap: () => _openDetail(context, sale),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openDetail(BuildContext context, Sale sale) async {
    await context.pushNamed(
      AppRouter.saleDetailName,
      pathParameters: <String, String>{'id': sale.id},
    );
  }

  /// Resolves the customer name for a card, handling the cash-sale case
  /// where `customerId` is null.
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
// Date filter chips
// -----------------------------------------------------------------------------

class _DateFilterChips extends StatelessWidget {
  const _DateFilterChips({
    required this.selected,
    required this.customRange,
    required this.onChanged,
  });

  final _SalesDateFilter selected;
  final DateTimeRange? customRange;
  final Future<void> Function(_SalesDateFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _chip(context, 'الكل', _SalesDateFilter.all),
          const SizedBox(width: 8),
          _chip(context, 'اليوم', _SalesDateFilter.today),
          const SizedBox(width: 8),
          _chip(context, 'هذا الأسبوع', _SalesDateFilter.thisWeek),
          const SizedBox(width: 8),
          _chip(context, 'هذا الشهر', _SalesDateFilter.thisMonth),
          const SizedBox(width: 8),
          _chip(context, 'هذا العام', _SalesDateFilter.thisYear),
          const SizedBox(width: 8),
          _chip(context, _customLabel(), _SalesDateFilter.custom),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    _SalesDateFilter value,
  ) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onChanged(value),
    );
  }

  String _customLabel() {
    if (selected == _SalesDateFilter.custom && customRange != null) {
      final DateFormat fmt = DateFormat('yy/MM/dd');
      return '${fmt.format(customRange!.start)} → '
          '${fmt.format(customRange!.end)}';
    }
    return 'نطاق مخصص';
  }
}

// -----------------------------------------------------------------------------
// Status filter chips
// -----------------------------------------------------------------------------

class _StatusFilterChips extends StatelessWidget {
  const _StatusFilterChips({
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _chip(context, 'كل الحالات', null),
          const SizedBox(width: 8),
          _chip(context, 'مسودة', SaleStatus.draft),
          const SizedBox(width: 8),
          _chip(context, 'مؤكدة', SaleStatus.confirmed),
          const SizedBox(width: 8),
          _chip(context, 'ملغاة', SaleStatus.cancelled),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String? value) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onChanged(value),
    );
  }
}

// -----------------------------------------------------------------------------
// Payment filter chips
// -----------------------------------------------------------------------------

class _PaymentFilterChips extends StatelessWidget {
  const _PaymentFilterChips({
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _chip(context, 'كل المدفوعات', null),
          const SizedBox(width: 8),
          _chip(context, 'غير مدفوع', PaymentStatus.unpaid),
          const SizedBox(width: 8),
          _chip(context, 'مدفوع جزئيًا', PaymentStatus.partial),
          const SizedBox(width: 8),
          _chip(context, 'مدفوع', PaymentStatus.paid),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String? value) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onChanged(value),
    );
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
