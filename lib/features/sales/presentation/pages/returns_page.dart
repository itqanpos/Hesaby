// lib/features/sales/presentation/pages/returns_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/entities/sale_return.dart';
import '../../domain/repositories/sales_repository.dart';
import '../dialogs/sales_filter_sheet.dart';
import '../providers/sales_providers.dart';

/// Returns list page — mirrors the layout of the sales page.
///
/// * KPI overview (this month / drafts / confirmed / cancelled).
/// * Search by return number, sale invoice, or customer name.
/// * Compact filter button with an active-count badge.
/// * Tapping a return opens a bottom sheet with its items.
class ReturnsPage extends ConsumerStatefulWidget {
  const ReturnsPage({super.key});

  @override
  ConsumerState<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends ConsumerState<ReturnsPage> {
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

  bool _matches(
    SaleReturn r,
    Map<String, String> customerNames,
    Map<String, String> invoiceBySaleId,
  ) {
    if (_filter.status != null && r.status != _filter.status) {
      return false;
    }

    final DateTime localDate = r.returnDate.toLocal();
    final DateTime? from = _filter.fromDate;
    final DateTime? to = _filter.toDate;
    if (from != null && localDate.isBefore(from)) {
      return false;
    }
    if (to != null && localDate.isAfter(to)) {
      return false;
    }

    final String trimmed = _searchQuery.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return true;
    }

    final String rn = (r.returnNumber ?? '').toLowerCase();
    if (rn.contains(trimmed)) {
      return true;
    }

    final String saleInv = (invoiceBySaleId[r.saleId] ?? '').toLowerCase();
    if (saleInv.contains(trimmed)) {
      return true;
    }

    final String? customerId = r.customerId;
    if (customerId != null) {
      final String name = (customerNames[customerId] ?? '').toLowerCase();
      if (name.contains(trimmed)) {
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SaleReturn>> returnsAsync =
        ref.watch(returnsProvider);
    final AsyncValue<List<Customer>> customersAsync =
        ref.watch(customersProvider);
    final AsyncValue<List<Sale>> salesAsync = ref.watch(salesProvider);

    final bool anyLoading = returnsAsync.isLoading ||
        customersAsync.isLoading ||
        salesAsync.isLoading;
    final Object? firstError =
        returnsAsync.error ?? customersAsync.error ?? salesAsync.error;

    return AppShell(
      appBar: AppBar(title: const Text('المرتجعات')),
      body: Builder(
        builder: (BuildContext context) {
          if (anyLoading) {
            return const AppLoader();
          }

          if (firstError != null) {
            return AppErrorView(
              title: 'تعذّر تحميل المرتجعات',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(returnsProvider);
                ref.invalidate(customersProvider);
                ref.invalidate(salesProvider);
              },
            );
          }

          final List<SaleReturn> allReturns =
              returnsAsync.value ?? const <SaleReturn>[];
          final List<Customer> customers =
              customersAsync.value ?? const <Customer>[];
          final List<Sale> sales = salesAsync.value ?? const <Sale>[];

          final Map<String, String> customerNames = <String, String>{
            for (final Customer c in customers) c.id: c.name,
          };
          final Map<String, String> invoiceBySaleId = <String, String>{
            for (final Sale s in sales)
              if (s.invoiceNumber != null) s.id: s.invoiceNumber!,
          };

          final List<SaleReturn> filtered = allReturns
              .where((SaleReturn r) =>
                  _matches(r, customerNames, invoiceBySaleId))
              .toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- KPI ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: _ReturnsKpiRow(returns: allReturns),
              ),

              // ---- Search + filter ----
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: AppTextField(
                        controller: _searchController,
                        hint: 'ابحث برقم المرتجع أو الفاتورة أو العميل',
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

              // ---- Active filter chips ----
              if (_filter.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ActiveChips(
                    filter: _filter,
                    onClearAll: _clearAllFilters,
                  ),
                ),

              // ---- List ----
              Expanded(
                child: allReturns.isEmpty
                    ? const AppEmptyView(
                        icon: Icons.assignment_return_outlined,
                        title: 'لا توجد مرتجعات',
                        message: 'لم يتم تسجيل أي مرتجع حتى الآن.',
                      )
                    : filtered.isEmpty
                        ? AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message:
                                'لم يُطابق أي مرتجع الفلاتر المحددة.',
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
                              final SaleReturn r = filtered[index];
                              return _ReturnCard(
                                saleReturn: r,
                                customerName: _resolveCustomerName(
                                  customerNames,
                                  r.customerId,
                                ),
                                saleInvoice:
                                    invoiceBySaleId[r.saleId] ?? '—',
                                onTap: () => _openDetail(context, r),
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

  Future<void> _openDetail(BuildContext context, SaleReturn r) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          _ReturnDetailSheet(saleReturn: r),
    );
  }

  static String _resolveCustomerName(
    Map<String, String> customerNames,
    String? customerId,
  ) {
    if (customerId == null) {
      return 'بدون عميل';
    }
    return customerNames[customerId] ?? 'عميل محذوف';
  }
}

// ============================================================================
// KPI row
// ============================================================================

class _ReturnsKpiRow extends StatelessWidget {
  const _ReturnsKpiRow({required this.returns});

  final List<SaleReturn> returns;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    double monthTotal = 0;
    int monthCount = 0;
    int draftCount = 0;
    int cancelledThisMonth = 0;

    for (final SaleReturn r in returns) {
      final DateTime d = r.returnDate.toLocal();
      final bool sameMonth = d.year == now.year && d.month == now.month;
      if (r.isConfirmed && sameMonth) {
        monthTotal += r.total;
        monthCount++;
      }
      if (r.isDraft) {
        draftCount++;
      }
      if (r.isCancelled && sameMonth) {
        cancelledThisMonth++;
      }
    }

    final NumberFormat money = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.assignment_return_outlined,
                iconColor: const Color(0xFF0288D1),
                label: 'قيمة المرتجعات (الشهر)',
                value: money.format(monthTotal),
                subtitle: '$monthCount مرتجع',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.edit_note_outlined,
                iconColor: const Color(0xFFE65100),
                label: 'مسودات',
                value: '$draftCount',
                subtitle: 'بحاجة لتأكيد',
                emphasize: draftCount > 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.check_circle_outline,
                iconColor: const Color(0xFF0F7B6C),
                label: 'مؤكدة (الشهر)',
                value: '$monthCount',
                subtitle: 'مرتجع',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.cancel_outlined,
                iconColor: const Color(0xFFC62828),
                label: 'ملغاة (الشهر)',
                value: '$cancelledThisMonth',
                subtitle: 'مرتجع',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
    this.emphasize = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String subtitle;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasize
              ? iconColor.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: emphasize ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: emphasize ? iconColor : scheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Filter button
// ============================================================================

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

// ============================================================================
// Active chips summary
// ============================================================================

class _ActiveChips extends StatelessWidget {
  const _ActiveChips({
    required this.filter,
    required this.onClearAll,
  });

  final SalesFilter filter;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[];

    if (filter.dateFilter != SalesDateFilter.all) {
      chips.add(Chip(
        label: Text(_dateLabel()),
        visualDensity: VisualDensity.compact,
      ));
    }
    if (filter.status != null) {
      chips.add(Chip(
        label: Text(_statusLabel(filter.status!)),
        visualDensity: VisualDensity.compact,
      ));
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
      case ReturnStatus.draft:
        return 'مسودة';
      case ReturnStatus.confirmed:
        return 'مؤكد';
      case ReturnStatus.cancelled:
        return 'ملغى';
      default:
        return status;
    }
  }
}

// ============================================================================
// Return card
// ============================================================================

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({
    required this.saleReturn,
    required this.customerName,
    required this.saleInvoice,
    required this.onTap,
  });

  final SaleReturn saleReturn;
  final String customerName;
  final String saleInvoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final NumberFormat money = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final DateFormat date = DateFormat.yMd('ar_EG');

    final (Color badgeBg, Color badgeFg) =
        _returnStatusColors(scheme, saleReturn.status);

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
                child: const Icon(Icons.assignment_return_outlined),
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
                            saleReturn.returnNumber ?? 'بدون رقم',
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
                              _returnStatusLabel(saleReturn.status),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: badgeFg,
                                fontWeight: FontWeight.w700,
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
                    const SizedBox(height: 2),
                    Text(
                      'فاتورة: $saleInvoice',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Text(
                          date.format(saleReturn.returnDate.toLocal()),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          money.format(saleReturn.total),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${_refundMethodLabel(saleReturn.refundMethod)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
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

// ============================================================================
// Return detail sheet
// ============================================================================

class _ReturnDetailSheet extends ConsumerWidget {
  const _ReturnDetailSheet({required this.saleReturn});

  final SaleReturn saleReturn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat money = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final NumberFormat qty = NumberFormat.decimalPattern('ar_EG');
    final AsyncValue<List<SaleReturnItem>> itemsAsync =
        ref.watch(returnItemsProvider(saleReturn.id));

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.assignment_return_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    saleReturn.returnNumber ?? 'تفاصيل المرتجع',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(
                  _returnStatusLabel(saleReturn.status),
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                Text(
                  _refundMethodLabel(saleReturn.refundMethod),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            itemsAsync.when(
              loading: () => const SizedBox(
                height: 100,
                child: AppLoader(),
              ),
              error: (Object error, StackTrace _) => Text(
                'تعذّر تحميل بنود المرتجع.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
              data: (List<SaleReturnItem> items) {
                if (items.isEmpty) {
                  return Text(
                    'لا توجد بنود.',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final SaleReturnItem it in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '${qty.format(it.quantity)} × '
                                    '${money.format(it.unitPrice)}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                Text(
                                  money.format(it.lineTotal),
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(
                  'إجمالي المرتجع',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  money.format(saleReturn.total),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Localization helpers
// ============================================================================

String _returnStatusLabel(String status) {
  switch (status) {
    case ReturnStatus.draft:
      return 'مسودة';
    case ReturnStatus.confirmed:
      return 'مؤكد';
    case ReturnStatus.cancelled:
      return 'ملغى';
    default:
      return 'غير معروف';
  }
}

(Color background, Color foreground) _returnStatusColors(
  ColorScheme scheme,
  String status,
) {
  switch (status) {
    case ReturnStatus.draft:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    case ReturnStatus.confirmed:
      return (scheme.primaryContainer, scheme.onPrimaryContainer);
    case ReturnStatus.cancelled:
      return (scheme.errorContainer, scheme.onErrorContainer);
    default:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
  }
}

String _refundMethodLabel(String method) {
  switch (method) {
    case RefundMethod.cash:
      return 'نقدي';
    case RefundMethod.card:
      return 'بطاقة';
    case RefundMethod.creditNote:
      return 'رصيد';
    case RefundMethod.none:
      return 'بدون استرداد';
    default:
      return method;
  }
}

String _errorMessage(Object error) {
  if (error is ReturnException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(ReturnFailureType type) {
  switch (type) {
    case ReturnFailureType.network:
      return 'تعذّر الاتصال بالخادم.';
    case ReturnFailureType.unauthorized:
      return 'انتهت صلاحية الجلسة.';
    case ReturnFailureType.notFound:
      return 'المرتجع غير موجود.';
    case ReturnFailureType.saleNotConfirmed:
      return 'الفاتورة الأصلية غير مؤكدة.';
    case ReturnFailureType.emptyReturn:
      return 'المرتجع بدون بنود.';
    case ReturnFailureType.excessiveQuantity:
      return 'الكمية تتجاوز المتاح.';
    case ReturnFailureType.creditNoteRequiresCustomer:
      return 'استرداد الرصيد يتطلب عميلًا.';
    case ReturnFailureType.invalidStatusTransition:
      return 'لا يمكن التعديل في الحالة الحالية.';
    case ReturnFailureType.immutableConfirmedReturn:
      return 'المرتجع المؤكد غير قابل للتعديل.';
    case ReturnFailureType.referenceNotFound:
      return 'أحد المراجع غير موجود.';
    case ReturnFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات.';
    case ReturnFailureType.unknown:
      return 'تعذّر إتمام العملية.';
  }
}
