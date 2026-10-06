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
import '../../../pos/domain/entities/receipt.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../dialogs/sale_print_dialog.dart';
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
/// search across invoice number and customer name. The detail view is
/// presented as a modal dialog (`_SaleDetailDialog`) rather than a
/// separate route.
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

    // Custom range: open a date-range picker. Keep the previous custom
    // range as the initial selection if the user has one already.
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
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _SaleDetailDialog(sale: sale),
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
// Sale detail dialog
// -----------------------------------------------------------------------------

class _SaleDetailDialog extends ConsumerStatefulWidget {
  const _SaleDetailDialog({required this.sale});

  final Sale sale;

  @override
  ConsumerState<_SaleDetailDialog> createState() => _SaleDetailDialogState();
}

class _SaleDetailDialogState extends ConsumerState<_SaleDetailDialog> {
  bool _isActing = false;

  @override
  Widget build(BuildContext context) {
    // Re-read the sale from the current providers so that the dialog
    // reflects any state change caused by confirm / cancel actions.
    final AsyncValue<List<Sale>> salesAsync = ref.watch(salesProvider);
    final AsyncValue<List<SaleItem>> itemsAsync =
        ref.watch(saleItemsProvider(widget.sale.id));
    final AsyncValue<List<Customer>> customersAsync =
        ref.watch(customersProvider);
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    final bool anyLoading = salesAsync.isLoading ||
        itemsAsync.isLoading ||
        customersAsync.isLoading ||
        productsAsync.isLoading ||
        unitsAsync.isLoading;

    if (anyLoading) {
      return AlertDialog(
        content: const SizedBox(
          width: 480,
          height: 320,
          child: AppLoader(),
        ),
        actions: <Widget>[
          AppButton(
            label: 'إغلاق',
            variant: AppButtonVariant.text,
            onPressed: _isActing
                ? null
                : () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    final List<Sale> sales = salesAsync.value ?? const <Sale>[];
    final Sale current = _findSale(sales, widget.sale.id) ?? widget.sale;
    final List<SaleItem> items =
        itemsAsync.value ?? const <SaleItem>[];
    final List<Customer> customers =
        customersAsync.value ?? const <Customer>[];
    final List<Product> products =
        productsAsync.value ?? const <Product>[];
    final List<Unit> units = unitsAsync.value ?? const <Unit>[];

    final String customerName = _resolveCustomerName(
      customers,
      current.customerId,
    );
    final Map<String, String> productNames = <String, String>{
      for (final Product product in products) product.id: product.name,
    };
    final Map<String, String> unitNames = <String, String>{
      for (final Unit unit in units) unit.id: unit.name,
    };

    return AlertDialog(
      title: Text(
        (current.invoiceNumber != null &&
                current.invoiceNumber!.isNotEmpty)
            ? 'فاتورة: ${current.invoiceNumber}'
            : 'تفاصيل الفاتورة',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _HeaderBlock(sale: current, customerName: customerName),
              const SizedBox(height: 16),
              Text(
                'البنود',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Text(
                  'لا توجد بنود.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                for (final SaleItem item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ItemRow(
                      item: item,
                      productName:
                          productNames[item.productId] ?? 'منتج محذوف',
                      unitName: unitNames[item.unitId] ?? 'وحدة',
                    ),
                  ),
              const SizedBox(height: 12),
              const Divider(),
              _TotalsBlock(sale: current),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'طباعة',
          icon: Icons.print_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: _isActing || items.isEmpty
              ? null
              : () => _printSale(
                    current,
                    items,
                    customerName,
                    productNames,
                    unitNames,
                    customers,
                  ),
        ),
        if (current.canEdit)
          AppButton(
            label: 'تعديل',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: _isActing
                ? null
                : () {
                    Navigator.of(context).pop();
                    context.pushNamed(
                      AppRouter.saleEditName,
                      pathParameters: <String, String>{'id': current.id},
                    );
                  },
          ),
        if (current.isDraft)
          AppButton(
            label: 'تأكيد',
            icon: Icons.check_circle_outline,
            isLoading: _isActing,
            onPressed: _isActing
                ? null
                : () => _confirmSale(current),
          ),
        if (current.canTransition)
          AppButton(
            label: 'إلغاء الفاتورة',
            icon: Icons.cancel_outlined,
            variant: AppButtonVariant.danger,
            onPressed: _isActing
                ? null
                : () => _cancelSale(current),
          ),
        AppButton(
          label: 'إغلاق',
          variant: AppButtonVariant.text,
          onPressed: _isActing
              ? null
              : () => Navigator.of(context).pop(),
        ),
      ],
      backgroundColor: Theme.of(context).colorScheme.surface,
      scrollable: false,
    );
  }

  Future<void> _confirmSale(Sale sale) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('تأكيد الفاتورة'),
        content: const Text(
          'سيتم تأكيد الفاتورة وخصم الكميات من المخزون. '
          'لا يمكن التعديل بعد التأكيد.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'رجوع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'تأكيد',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isActing = true);

    try {
      await ref.read(salesProvider.notifier).confirmSale(sale.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد الفاتورة')),
      );
    } on SaleException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(context, error);
    } on Object {
      if (!mounted) {
        return;
      }
      _showError(
        context,
        const SaleException(type: SalesFailureType.unknown),
      );
    } finally {
      if (mounted) {
        setState(() => _isActing = false);
      }
    }
  }

  Future<void> _cancelSale(Sale sale) async {
    final bool wasConfirmed = sale.isConfirmed;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: Text(
          wasConfirmed
              ? 'سيتم إلغاء الفاتورة وإرجاع الكميات إلى المخزون.'
              : 'سيتم إلغاء الفاتورة. لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'رجوع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'إلغاء الفاتورة',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isActing = true);

    try {
      await ref.read(salesProvider.notifier).cancelSale(sale.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الفاتورة')),
      );
    } on SaleException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(context, error);
    } on Object {
      if (!mounted) {
        return;
      }
      _showError(
        context,
        const SaleException(type: SalesFailureType.unknown),
      );
    } finally {
      if (mounted) {
        setState(() => _isActing = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Print
  // ---------------------------------------------------------------------------

  /// Builds a [Receipt] snapshot from the current sale and opens the
  /// 80 mm / A4 print dialog.
  Future<void> _printSale(
    Sale sale,
    List<SaleItem> items,
    String customerName,
    Map<String, String> productNames,
    Map<String, String> unitNames,
    List<Customer> customers,
  ) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('لا يمكن طباعة فاتورة بدون بنود.'),
          ),
        );
      return;
    }

    final CompanyContextState contextState =
        ref.read(companyContextProvider);

    final Receipt receipt = _buildReceipt(
      sale: sale,
      items: items,
      customerName: customerName,
      productNames: productNames,
      unitNames: unitNames,
      contextState: contextState,
    );

    await showSalePrintDialog(context: context, receipt: receipt);
  }

  /// Builds the [Receipt] value object passed to the print dialog.
  ///
  /// The customer's *current* balance is informational only. For a sale
  /// that may have been printed long after it was confirmed, we cannot
  /// reconstruct the balance that existed before the sale — payments,
  /// later sales and adjustments since then would all be invisible.
  /// We therefore do not pass `previousBalance` / `newBalance`.
  Receipt _buildReceipt({
    required Sale sale,
    required List<SaleItem> items,
    required String customerName,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
    required CompanyContextState contextState,
  }) {
    return Receipt(
      saleId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      dateTime: sale.saleDate,
      companyName: contextState.currentCompany?.name ?? '—',
      branchName: contextState.currentBranch?.name ?? '—',
      lines: <ReceiptLine>[
        for (final SaleItem item in items)
          ReceiptLine(
            productName: productNames[item.productId] ?? 'منتج محذوف',
            unitName: unitNames[item.unitId] ?? 'وحدة',
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            lineTotal: item.lineTotal,
          ),
      ],
      subtotal: sale.subtotal,
      discount: sale.discount,
      taxAmount: sale.taxAmount,
      total: sale.total,
      paidAmount: sale.paidAmount,
      change: 0,
      customerName: sale.customerId != null ? customerName : null,
      previousBalance: null,
      newBalance: null,
    );
  }

  static Sale? _findSale(List<Sale> sales, String id) {
    for (final Sale sale in sales) {
      if (sale.id == id) {
        return sale;
      }
    }
    return null;
  }

  /// Resolves a customer id to a display name.
  ///
  /// Returns "عميل نقدي" when [customerId] is null (cash sale), and
  /// "عميل محذوف" when no matching customer exists in the loaded list.
  static String _resolveCustomerName(
    List<Customer> customers,
    String? customerId,
  ) {
    if (customerId == null) {
      return 'عميل نقدي';
    }
    for (final Customer customer in customers) {
      if (customer.id == customerId) {
        return customer.name;
      }
    }
    return 'عميل محذوف';
  }
}

// -----------------------------------------------------------------------------
// Header block
// -----------------------------------------------------------------------------

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({required this.sale, required this.customerName});

  final Sale sale;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DateFormat dateTimeFormat = DateFormat.yMd('ar_EG').add_Hm();

    final (Color badgeBg, Color badgeFg) = _statusColors(
      scheme,
      sale.status,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                customerName,
                style: theme.textTheme.titleMedium,
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
                  vertical: 3,
                ),
                child: Text(
                  _statusLabel(sale.status),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: badgeFg,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          dateTimeFormat.format(sale.saleDate.toLocal()),
          style: theme.textTheme.bodySmall,
        ),
        if (sale.hasNotes) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            sale.notes!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Item row
// -----------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.productName,
    required this.unitName,
  });

  final SaleItem item;
  final String productName;
  final String unitName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat numberFormat = NumberFormat.decimalPattern('ar_EG');
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    productName,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${numberFormat.format(item.quantity)} $unitName × '
                    '${moneyFormat.format(item.unitPrice)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              moneyFormat.format(item.lineTotal),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Totals block
// -----------------------------------------------------------------------------

class _TotalsBlock extends StatelessWidget {
  const _TotalsBlock({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _line(theme, 'المجموع الفرعي', moneyFormat.format(sale.subtotal)),
        const SizedBox(height: 4),
        _line(theme, 'الخصم', moneyFormat.format(sale.discount)),
        const SizedBox(height: 4),
        _line(theme, 'الضريبة', moneyFormat.format(sale.taxAmount)),
        const Divider(height: 20),
        _line(
          theme,
          'الإجمالي',
          moneyFormat.format(sale.total),
          emphasized: true,
        ),
        const SizedBox(height: 4),
        _line(
          theme,
          'المدفوع',
          moneyFormat.format(sale.paidAmount),
        ),
        if (sale.amountDue > 0) ...<Widget>[
          const SizedBox(height: 4),
          _line(
            theme,
            'المتبقي',
            moneyFormat.format(sale.amountDue),
            emphasized: true,
            color: theme.colorScheme.error,
          ),
        ],
      ],
    );
  }

  Widget _line(
    ThemeData theme,
    String label,
    String value, {
    bool emphasized = false,
    Color? color,
  }) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: emphasized
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color ?? theme.colorScheme.primary,
                )
              : theme.textTheme.bodyMedium,
        ),
      ],
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

void _showError(BuildContext context, SaleException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
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
