// lib/features/purchases/presentation/pages/purchases_page.dart

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
import '../../../suppliers/domain/entities/supplier.dart';
import '../../../suppliers/presentation/providers/supplier_providers.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../providers/purchase_providers.dart';

/// Purchases list page.
///
/// Layout (top → bottom):
/// 1. KPI row (total / drafts / confirmed this month / value this month).
/// 2. Search by invoice number or supplier name.
/// 3. Status filter chips + Sort dropdown.
/// 4. Rich purchase card with status badge, supplier, date and total.
///
/// All filtering and sorting are local; the underlying list is capped by
/// the repository (`defaultLimit` = 100) and covers the vast majority of
/// SME usage without pagination.
class PurchasesPage extends ConsumerStatefulWidget {
  const PurchasesPage({super.key});

  @override
  ConsumerState<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends ConsumerState<PurchasesPage> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String? _statusFilter;
  _SortOption _sort = _SortOption.dateDesc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final CompanyContextState contextState =
        ref.watch(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;

    final AsyncValue<List<Purchase>> purchasesAsync =
        ref.watch(purchasesProvider);
    final AsyncValue<List<Supplier>> suppliersAsync =
        ref.watch(suppliersProvider);

    final bool anyLoading =
        purchasesAsync.isLoading || suppliersAsync.isLoading;
    final Object? firstError = purchasesAsync.error ?? suppliersAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('فواتير الشراء'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: anyLoading || firstError != null
                ? null
                : () {
                    ref.invalidate(purchasesProvider);
                    ref.invalidate(suppliersProvider);
                  },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'إضافة فاتورة',
            onPressed: anyLoading || firstError != null || branchId == null
                ? null
                : () => context.pushNamed(AppRouter.purchaseNewName),
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
              title: 'تعذّر تحميل فواتير الشراء',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(purchasesProvider);
                ref.invalidate(suppliersProvider);
              },
            );
          }

          if (branchId == null) {
            return const AppEmptyView(
              icon: Icons.store_mall_directory_outlined,
              title: 'لم يتم اختيار فرع',
              message: 'اختر فرعًا من الصفحة الرئيسية لعرض فواتير الشراء.',
            );
          }

          final List<Purchase> allPurchases =
              purchasesAsync.value ?? const <Purchase>[];
          final List<Supplier> suppliers =
              suppliersAsync.value ?? const <Supplier>[];

          final Map<String, String> supplierNames = <String, String>{
            for (final Supplier supplier in suppliers)
              supplier.id: supplier.name,
          };

          final List<Purchase> visible = _applyFiltersAndSort(
            allPurchases,
            supplierNames,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- KPI ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _KpiRow(purchases: allPurchases),
              ),

              // ---- Search ----
              AppTextField(
                controller: _searchController,
                hint: 'ابحث برقم الفاتورة أو اسم المورد',
                prefixIcon: Icons.search,
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
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

              const SizedBox(height: 10),

              // ---- Status + Sort ----
              _FilterBar(
                status: _statusFilter,
                sort: _sort,
                onStatusChanged: (String? v) {
                  setState(() => _statusFilter = v);
                },
                onSortChanged: (_SortOption v) {
                  setState(() => _sort = v);
                },
              ),

              const SizedBox(height: 8),

              // ---- List ----
              Expanded(
                child: allPurchases.isEmpty
                    ? AppEmptyView(
                        icon: Icons.receipt_long_outlined,
                        title: 'لا توجد فواتير شراء',
                        message:
                            'ابدأ بتسجيل أول فاتورة شراء من أحد الموردين.',
                        action: AppButton(
                          label: 'إضافة فاتورة',
                          icon: Icons.add,
                          onPressed: () =>
                              context.pushNamed(AppRouter.purchaseNewName),
                        ),
                      )
                    : visible.isEmpty
                        ? AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message:
                                'لم تُطابق أي فاتورة معايير البحث أو الفلترة.',
                            action: AppButton(
                              label: 'مسح الفلاتر',
                              icon: Icons.filter_alt_off_outlined,
                              variant: AppButtonVariant.secondary,
                              onPressed: _clearAllFilters,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder:
                                (BuildContext context, int index) {
                              final Purchase purchase = visible[index];
                              final String supplierName =
                                  supplierNames[purchase.supplierId] ??
                                      'مورد محذوف';
                              return _PurchaseCard(
                                purchase: purchase,
                                supplierName: supplierName,
                                onTap: () => _openDetail(context, purchase),
                                onEdit: purchase.canEdit
                                    ? () => _openEdit(context, purchase)
                                    : null,
                                onConfirm: purchase.isDraft
                                    ? () => _confirmPurchase(
                                          context,
                                          purchase,
                                        )
                                    : null,
                                onCancel: purchase.canTransition
                                    ? () => _confirmCancel(
                                          context,
                                          purchase,
                                        )
                                    : null,
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
  // Filtering + sorting
  // ---------------------------------------------------------------------------

  List<Purchase> _applyFiltersAndSort(
    List<Purchase> purchases,
    Map<String, String> supplierNames,
  ) {
    final String trimmed = _searchQuery.trim().toLowerCase();

    Iterable<Purchase> result = purchases;

    // ---- Status filter ----
    if (_statusFilter != null) {
      result = result.where((p) => p.status == _statusFilter);
    }

    // ---- Search ----
    if (trimmed.isNotEmpty) {
      result = result.where((Purchase p) {
        final String invoice =
            (p.invoiceNumber ?? '').toLowerCase();
        if (invoice.contains(trimmed)) {
          return true;
        }
        final String supplier =
            (supplierNames[p.supplierId] ?? '').toLowerCase();
        return supplier.contains(trimmed);
      });
    }

    // ---- Sort ----
    final List<Purchase> list = result.toList(growable: false);
    switch (_sort) {
      case _SortOption.dateDesc:
        list.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      case _SortOption.dateAsc:
        list.sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
      case _SortOption.totalDesc:
        list.sort((a, b) => b.total.compareTo(a.total));
      case _SortOption.totalAsc:
        list.sort((a, b) => a.total.compareTo(b.total));
      case _SortOption.invoiceAsc:
        list.sort((a, b) => (a.invoiceNumber ?? '')
            .compareTo(b.invoiceNumber ?? ''));
      case _SortOption.invoiceDesc:
        list.sort((a, b) => (b.invoiceNumber ?? '')
            .compareTo(a.invoiceNumber ?? ''));
    }

    return list;
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _statusFilter = null;
      _sort = _SortOption.dateDesc;
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _openDetail(BuildContext context, Purchase purchase) {
    context.pushNamed(
      AppRouter.purchaseDetailName,
      pathParameters: <String, String>{'id': purchase.id},
    );
  }

  void _openEdit(BuildContext context, Purchase purchase) {
    context.pushNamed(
      AppRouter.purchaseEditName,
      pathParameters: <String, String>{'id': purchase.id},
    );
  }

  Future<void> _confirmPurchase(
    BuildContext context,
    Purchase purchase,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('تأكيد الفاتورة'),
        content: const Text(
          'سيتم تأكيد الفاتورة وإضافة الكميات إلى المخزون. '
          'لا يمكن التعديل بعد التأكيد.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
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

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(purchasesProvider.notifier)
          .confirmPurchase(purchase.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد الفاتورة')),
      );
    } on PurchaseException catch (error) {
      if (!context.mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _confirmCancel(
    BuildContext context,
    Purchase purchase,
  ) async {
    final bool wasConfirmed = purchase.isConfirmed;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: Text(
          wasConfirmed
              ? 'سيتم إلغاء الفاتورة وعكس كميات المخزون. '
                  'قد يفشل الإلغاء إذا استُهلكت الكميات.'
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

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(purchasesProvider.notifier)
          .cancelPurchase(purchase.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الفاتورة')),
      );
    } on PurchaseException catch (error) {
      if (!context.mounted) return;
      _showError(context, error);
    }
  }
}

// ============================================================================
// KPI row
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.purchases});

  final List<Purchase> purchases;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    int draft = 0;
    int confirmed = 0;
    int cancelled = 0;
    double monthValue = 0;

    for (final Purchase p in purchases) {
      if (p.isDraft) draft++;
      if (p.isConfirmed) confirmed++;
      if (p.isCancelled) cancelled++;

      if (p.isConfirmed) {
        final DateTime d = p.purchaseDate.toLocal();
        if (d.year == now.year && d.month == now.month) {
          monthValue += p.total;
        }
      }
    }

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _KpiCard(
                icon: Icons.edit_note_outlined,
                label: 'مسودات',
                value: '$draft',
                color: const Color(0xFFE65100),
                emphasize: draft > 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.check_circle_outline,
                label: 'مؤكدة',
                value: '$confirmed',
                color: const Color(0xFF0F7B6C),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiCard(
                icon: Icons.cancel_outlined,
                label: 'ملغاة',
                value: '$cancelled',
                color: const Color(0xFFC62828),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _MonthValueCard(
          purchasesThisMonth:
              purchases.where((p) => p.isConfirmed).length,
          monthValue: monthValue,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize
              ? color.withValues(alpha: 0.5)
              : scheme.outlineVariant,
          width: emphasize ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: emphasize ? color : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthValueCard extends StatelessWidget {
  const _MonthValueCard({
    required this.purchasesThisMonth,
    required this.monthValue,
  });

  final int purchasesThisMonth;
  final double monthValue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.10),
            scheme.primary.withValues(alpha: 0.04),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.shopping_bag_outlined,
              color: scheme.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'مشتريات مؤكدة هذا الشهر',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  moneyFormat.format(monthValue),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  '$purchasesThisMonth فاتورة',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
// Filter bar (status chips + sort)
// ============================================================================

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.sort,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  final String? status;
  final _SortOption sort;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<_SortOption> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('الكل'),
            selected: status == null,
            onSelected: (_) => onStatusChanged(null),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('مسودة'),
            selected: status == PurchaseStatus.draft,
            onSelected: (_) => onStatusChanged(PurchaseStatus.draft),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('مؤكدة'),
            selected: status == PurchaseStatus.confirmed,
            onSelected: (_) => onStatusChanged(PurchaseStatus.confirmed),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('ملغاة'),
            selected: status == PurchaseStatus.cancelled,
            onSelected: (_) => onStatusChanged(PurchaseStatus.cancelled),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 10),
          _SortChip(
            sort: sort,
            onChanged: onSortChanged,
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.sort,
    required this.onChanged,
  });

  final _SortOption sort;
  final ValueChanged<_SortOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SortOption>(
      tooltip: 'ترتيب',
      onSelected: onChanged,
      itemBuilder: (BuildContext _) => <PopupMenuEntry<_SortOption>>[
        for (final _SortOption option in _SortOption.values)
          CheckedPopupMenuItem<_SortOption>(
            value: option,
            checked: option == sort,
            child: Text(_label(option)),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.sort, size: 16),
        label: Text(_label(sort)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  static String _label(_SortOption option) {
    switch (option) {
      case _SortOption.dateDesc:
        return 'الأحدث';
      case _SortOption.dateAsc:
        return 'الأقدم';
      case _SortOption.totalDesc:
        return 'الأعلى قيمة';
      case _SortOption.totalAsc:
        return 'الأقل قيمة';
      case _SortOption.invoiceAsc:
        return 'رقم الفاتورة ↑';
      case _SortOption.invoiceDesc:
        return 'رقم الفاتورة ↓';
    }
  }
}

// ============================================================================
// Purchase card
// ============================================================================

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    required this.purchase,
    required this.supplierName,
    required this.onTap,
    required this.onEdit,
    required this.onConfirm,
    required this.onCancel,
  });

  final Purchase purchase;
  final String supplierName;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final DateFormat dateFormat = DateFormat.yMd('ar_EG');

    final (Color badgeBg, Color badgeFg) = _statusColors(
      scheme,
      purchase.status,
    );
    final String statusLabel = _statusLabel(purchase.status);

    final String? invoice = purchase.invoiceNumber;
    final String headerTitle =
        (invoice != null && invoice.isNotEmpty)
            ? invoice
            : 'بدون رقم فاتورة';

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ---- Status avatar ----
              CircleAvatar(
                radius: 20,
                backgroundColor: badgeBg,
                foregroundColor: badgeFg,
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // ---- Content ----
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
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _StatusBadge(
                          label: statusLabel,
                          background: badgeBg,
                          foreground: badgeFg,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            supplierName,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateFormat.format(purchase.purchaseDate.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          moneyFormat.format(purchase.total),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ---- Menu ----
              _buildMenu(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final List<PopupMenuEntry<_PurchaseAction>> items =
        <PopupMenuEntry<_PurchaseAction>>[];

    if (onEdit != null) {
      items.add(
        const PopupMenuItem<_PurchaseAction>(
          value: _PurchaseAction.edit,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('تعديل'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }
    if (onConfirm != null) {
      items.add(
        const PopupMenuItem<_PurchaseAction>(
          value: _PurchaseAction.confirm,
          child: ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('تأكيد'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }
    if (onCancel != null) {
      items.add(
        const PopupMenuItem<_PurchaseAction>(
          value: _PurchaseAction.cancel,
          child: ListTile(
            leading: Icon(Icons.cancel_outlined),
            title: Text('إلغاء الفاتورة'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return const SizedBox(width: 24);
    }

    return PopupMenuButton<_PurchaseAction>(
      tooltip: 'خيارات',
      onSelected: (_PurchaseAction action) {
        switch (action) {
          case _PurchaseAction.edit:
            onEdit?.call();
          case _PurchaseAction.confirm:
            onConfirm?.call();
          case _PurchaseAction.cancel:
            onCancel?.call();
        }
      },
      itemBuilder: (BuildContext context) => items,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Enums
// ============================================================================

enum _PurchaseAction { edit, confirm, cancel }

enum _SortOption {
  dateDesc,
  dateAsc,
  totalDesc,
  totalAsc,
  invoiceAsc,
  invoiceDesc,
}

// ============================================================================
// Localization helpers
// ============================================================================

String _statusLabel(String status) {
  switch (status) {
    case PurchaseStatus.draft:
      return 'مسودة';
    case PurchaseStatus.confirmed:
      return 'مؤكدة';
    case PurchaseStatus.cancelled:
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
    case PurchaseStatus.draft:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    case PurchaseStatus.confirmed:
      return (scheme.primaryContainer, scheme.onPrimaryContainer);
    case PurchaseStatus.cancelled:
      return (scheme.errorContainer, scheme.onErrorContainer);
    default:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
  }
}

void _showError(BuildContext context, PurchaseException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _errorMessage(Object error) {
  if (error is PurchaseException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(PurchaseFailureType type) => switch (type) {
      PurchaseFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      PurchaseFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      PurchaseFailureType.notFound =>
        'الفاتورة المطلوبة غير موجودة أو تم حذفها.',
      PurchaseFailureType.invalidStatusTransition =>
        'لا يمكن إجراء هذه العملية على الفاتورة في حالتها الحالية.',
      PurchaseFailureType.emptyPurchase =>
        'لا يمكن تأكيد فاتورة بدون بنود. أضف منتجًا واحدًا على الأقل.',
      PurchaseFailureType.invoiceNumberConflict =>
        'يوجد فاتورة أخرى بنفس الرقم في هذه الشركة.',
      PurchaseFailureType.supplierNotFound =>
        'المورد المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.productNotFound =>
        'أحد المنتجات المختارة غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.unitNotFound =>
        'إحدى الوحدات المختارة غير متاحة. يرجى إعادة اختيارها.',
      PurchaseFailureType.insufficientStock =>
        'لا يمكن عكس الفاتورة؛ بعض الكميات استُهلكت بالفعل.',
      PurchaseFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الفواتير. يرجى المحاولة لاحقًا.',
      PurchaseFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };
