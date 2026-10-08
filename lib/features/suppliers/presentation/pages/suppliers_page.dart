// lib/features/suppliers/presentation/pages/suppliers_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../purchases/presentation/dialogs/supplier_payment_dialog.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../providers/supplier_providers.dart';
import '../providers/supplier_stats_providers.dart';

/// Supplier management page.
///
/// Layout (top → bottom):
/// 1. KPI row (total / active / inactive) — clickable status shortcuts.
/// 2. Search field (name / code / phone).
/// 3. Status chips + Sort dropdown.
/// 4. Enhanced supplier card showing the running balance.
class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  _StatusFilter _statusFilter = _StatusFilter.all;
  _SortOption _sort = _SortOption.nameAsc;

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
    final AsyncValue<List<Supplier>> suppliersAsync =
        ref.watch(suppliersProvider);
    final AsyncValue<SupplierCounts> countsAsync =
        ref.watch(supplierCountsProvider);
    final AsyncValue<Map<String, SupplierBalance>> balancesAsync =
        ref.watch(supplierBalancesProvider);

    final Map<String, SupplierBalance> balances =
        balancesAsync.valueOrNull ?? const <String, SupplierBalance>{};

    return AppShell(
      appBar: AppBar(
        title: const Text('الموردون'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: () {
              ref.invalidate(suppliersProvider);
              ref.invalidate(supplierCountsProvider);
              ref.invalidate(supplierBalancesProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'إضافة مورد',
            onPressed: () => _openSupplierForm(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: suppliersAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الموردين',
          message: _errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: () {
            ref.invalidate(suppliersProvider);
            ref.invalidate(supplierCountsProvider);
            ref.invalidate(supplierBalancesProvider);
          },
        ),
        data: (List<Supplier> suppliers) {
          final List<Supplier> visible = _filterAndSort(suppliers, balances);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- KPI ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _KpiRow(
                  counts: countsAsync.valueOrNull ??
                      const SupplierCounts.zero(),
                  isLoading: countsAsync.isLoading,
                  selected: _statusFilter,
                  onSelect: (_StatusFilter f) =>
                      setState(() => _statusFilter = f),
                ),
              ),

              // ---- Search ----
              AppTextField(
                controller: _searchController,
                hint: 'ابحث بالاسم أو الكود أو الهاتف',
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
                onChanged: (String v) => setState(() => _searchQuery = v),
              ),

              const SizedBox(height: 10),

              // ---- Filter + Sort ----
              _FilterBar(
                status: _statusFilter,
                sort: _sort,
                onStatusChanged: (v) => setState(() => _statusFilter = v),
                onSortChanged: (v) => setState(() => _sort = v),
              ),

              const SizedBox(height: 8),

              // ---- List ----
              Expanded(
                child: suppliers.isEmpty
                    ? AppEmptyView(
                        icon: Icons.local_shipping_outlined,
                        title: 'لا يوجد موردون',
                        message:
                            'ابدأ بإضافة أول مورد للشركة (مَن تشتري منه).',
                        action: AppButton(
                          label: 'إضافة مورد',
                          icon: Icons.add,
                          onPressed: () => _openSupplierForm(context),
                        ),
                      )
                    : visible.isEmpty
                        ? AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message:
                                'لم يُطابق أي مورد الفلاتر أو كلمة البحث.',
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
                              final Supplier supplier = visible[index];
                              return _SupplierCard(
                                supplier: supplier,
                                balance: balances[supplier.id] ??
                                    SupplierBalance.zero(
                                      supplierId: supplier.id,
                                    ),
                                onRecordPayment: () =>
                                    _recordPayment(context, supplier),
                                onEdit: () => _openSupplierForm(
                                  context,
                                  existing: supplier,
                                ),
                                onToggleActive: () =>
                                    _toggleActive(context, supplier),
                                onDelete: () =>
                                    _confirmDelete(context, supplier),
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

  List<Supplier> _filterAndSort(
    List<Supplier> suppliers,
    Map<String, SupplierBalance> balances,
  ) {
    final String q = _searchQuery.trim().toLowerCase();

    Iterable<Supplier> result = suppliers;

    // Status
    switch (_statusFilter) {
      case _StatusFilter.all:
        break;
      case _StatusFilter.active:
        result = result.where((s) => s.isActive);
      case _StatusFilter.inactive:
        result = result.where((s) => !s.isActive);
    }

    // Search
    if (q.isNotEmpty) {
      result = result.where((Supplier s) {
        final String name = s.name.toLowerCase();
        final String code = (s.code ?? '').toLowerCase();
        final String phone = (s.phone ?? '').toLowerCase();
        return name.contains(q) || code.contains(q) || phone.contains(q);
      });
    }

    final List<Supplier> list = result.toList(growable: false);

    switch (_sort) {
      case _SortOption.nameAsc:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _SortOption.nameDesc:
        list.sort((a, b) => b.name.compareTo(a.name));
      case _SortOption.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _SortOption.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _SortOption.balanceDesc:
        list.sort((a, b) {
          final double ba = balances[a.id]?.balance ?? 0;
          final double bb = balances[b.id]?.balance ?? 0;
          return bb.compareTo(ba);
        });
      case _SortOption.balanceAsc:
        list.sort((a, b) {
          final double ba = balances[a.id]?.balance ?? 0;
          final double bb = balances[b.id]?.balance ?? 0;
          return ba.compareTo(bb);
        });
    }

    return list;
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _statusFilter = _StatusFilter.all;
      _sort = _SortOption.nameAsc;
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _recordPayment(
    BuildContext context,
    Supplier supplier,
  ) async {
    final bool? saved = await showSupplierPaymentDialog(
      context: context,
      supplierId: supplier.id,
      supplierName: supplier.name,
    );
    if (saved == true && context.mounted) {
      ref.invalidate(supplierBalancesProvider);
    }
  }

  Future<void> _openSupplierForm(
    BuildContext context, {
    Supplier? existing,
  }) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _SupplierFormDialog(
        existing: existing,
      ),
    );

    if (!context.mounted || saved != true) {
      return;
    }

    ref.invalidate(supplierCountsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null ? 'تم إضافة المورد' : 'تم تحديث المورد',
        ),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    Supplier supplier,
  ) async {
    try {
      await ref.read(suppliersProvider.notifier).updateSupplier(
            supplierId: supplier.id,
            isActive: !supplier.isActive,
          );
      if (!context.mounted) return;
      ref.invalidate(supplierCountsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            supplier.isActive ? 'تم تعطيل المورد' : 'تم تفعيل المورد',
          ),
        ),
      );
    } on SupplierException catch (error) {
      if (!context.mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Supplier supplier,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف المورد'),
        content: Text(
          'هل تريد حذف "${supplier.name}"؟ لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'حذف',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(suppliersProvider.notifier).deleteSupplier(supplier.id);
      if (!context.mounted) return;
      ref.invalidate(supplierCountsProvider);
      ref.invalidate(supplierBalancesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المورد')),
      );
    } on SupplierException catch (error) {
      if (!context.mounted) return;
      _showError(context, error);
    }
  }
}

// ============================================================================
// KPI row
// ============================================================================

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.counts,
    required this.isLoading,
    required this.selected,
    required this.onSelect,
  });

  final SupplierCounts counts;
  final bool isLoading;
  final _StatusFilter selected;
  final ValueChanged<_StatusFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            icon: Icons.local_shipping_outlined,
            label: 'الإجمالي',
            value: isLoading ? '…' : counts.total.toString(),
            color: const Color(0xFF0288D1),
            isSelected: selected == _StatusFilter.all,
            onTap: () => onSelect(_StatusFilter.all),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.check_circle_outline,
            label: 'نشط',
            value: isLoading ? '…' : counts.active.toString(),
            color: const Color(0xFF0F7B6C),
            isSelected: selected == _StatusFilter.active,
            onTap: () => onSelect(_StatusFilter.active),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.pause_circle_outline,
            label: 'معطّل',
            value: isLoading ? '…' : counts.inactive.toString(),
            color: const Color(0xFF7B5E3A),
            isSelected: selected == _StatusFilter.inactive,
            onTap: () => onSelect(_StatusFilter.inactive),
          ),
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
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : scheme.outlineVariant,
              width: isSelected ? 1.8 : 1,
            ),
          ),
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
                  color: isSelected ? color : scheme.onSurface,
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
// Filter bar
// ============================================================================

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.sort,
    required this.onStatusChanged,
    required this.onSortChanged,
  });

  final _StatusFilter status;
  final _SortOption sort;
  final ValueChanged<_StatusFilter> onStatusChanged;
  final ValueChanged<_SortOption> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('الكل'),
            selected: status == _StatusFilter.all,
            onSelected: (_) => onStatusChanged(_StatusFilter.all),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('نشط'),
            selected: status == _StatusFilter.active,
            onSelected: (_) => onStatusChanged(_StatusFilter.active),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('معطّل'),
            selected: status == _StatusFilter.inactive,
            onSelected: (_) => onStatusChanged(_StatusFilter.inactive),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 10),
          _SortChip(sort: sort, onChanged: onSortChanged),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.sort, required this.onChanged});

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
      case _SortOption.nameAsc:
        return 'الاسم (أ-ي)';
      case _SortOption.nameDesc:
        return 'الاسم (ي-أ)';
      case _SortOption.newest:
        return 'الأحدث';
      case _SortOption.oldest:
        return 'الأقدم';
      case _SortOption.balanceDesc:
        return 'الأعلى رصيدًا';
      case _SortOption.balanceAsc:
        return 'الأقل رصيدًا';
    }
  }
}

// ============================================================================
// Supplier card
// ============================================================================

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.balance,
    required this.onRecordPayment,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final Supplier supplier;
  final SupplierBalance balance;
  final VoidCallback onRecordPayment;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isActive = supplier.isActive;

 final List<String> meta = <String>[];
    if (supplier.hasCode) {
      meta.add('كود: ${supplier.code}');
    }
    if (supplier.hasPhone) {
      meta.add(supplier.phone!);
    } else if (supplier.hasEmail) {
      meta.add(supplier.email!);
    }

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: isActive
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                foregroundColor: isActive
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                child: const Icon(Icons.local_shipping_outlined, size: 20),
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
                            supplier.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isActive)
                          _Badge(
                            label: 'معطّل',
                            background: scheme.surfaceContainerHighest,
                            foreground: scheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    if (meta.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        meta.join('  ·  '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    _BalanceLine(balance: balance, money: _money),
                  ],
                ),
              ),
              PopupMenuButton<_SupplierAction>(
                tooltip: 'خيارات',
                onSelected: (_SupplierAction action) {
                  switch (action) {
                    case _SupplierAction.recordPayment:
                      onRecordPayment();
                    case _SupplierAction.edit:
                      onEdit();
                    case _SupplierAction.toggleActive:
                      onToggleActive();
                    case _SupplierAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_SupplierAction>>[
                  const PopupMenuItem<_SupplierAction>(
                    value: _SupplierAction.recordPayment,
                    child: ListTile(
                      leading: Icon(Icons.payments_outlined),
                      title: Text('تسجيل دفعة'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<_SupplierAction>(
                    value: _SupplierAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('تعديل'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_SupplierAction>(
                    value: _SupplierAction.toggleActive,
                    child: ListTile(
                      leading: Icon(
                        isActive
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      title: Text(isActive ? 'تعطيل' : 'تفعيل'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<_SupplierAction>(
                    value: _SupplierAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('حذف'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Balance line
// ============================================================================

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.balance, required this.money});

  final SupplierBalance balance;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (!balance.hasActivity) {
      return Row(
        children: <Widget>[
          Icon(
            Icons.remove_circle_outline,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            'لا حركات',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final double b = balance.balance;
    final Color accent;
    final IconData icon;
    final String label;
    if (b > 0) {
      accent = scheme.error;
      icon = Icons.arrow_upward;
      label = 'مستحق للمورد';
    } else if (b < 0) {
      accent = const Color(0xFF0F7B6C);
      icon = Icons.arrow_downward;
      label = 'دفعة مقدمة';
    } else {
      accent = const Color(0xFF0F7B6C);
      icon = Icons.check_circle_outline;
      label = 'مسدَّد بالكامل';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              money.format(b.abs()),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
// Supplier form dialog (unchanged)
// ============================================================================

class _SupplierFormDialog extends ConsumerStatefulWidget {
  const _SupplierFormDialog({this.existing});

  final Supplier? existing;

  @override
  ConsumerState<_SupplierFormDialog> createState() =>
      _SupplierFormDialogState();
}

class _SupplierFormDialogState extends ConsumerState<_SupplierFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;

  bool _isSubmitting = false;
  SupplierFailureType? _failureType;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Supplier? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _codeController = TextEditingController(text: existing?.code ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _emailController = TextEditingController(text: existing?.email ?? '');
    _addressController = TextEditingController(text: existing?.address ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static String? _emptyToNull(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_failureType != null) {
      setState(() => _failureType = null);
    }

    final bool isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() => _isSubmitting = true);

    final SuppliersNotifier notifier = ref.read(suppliersProvider.notifier);
    final String name = _nameController.text.trim();
    final String? code = _emptyToNull(_codeController.text);
    final String? phone = _emptyToNull(_phoneController.text);
    final String? email = _emptyToNull(_emailController.text);
    final String? address = _emptyToNull(_addressController.text);
    final String? notes = _emptyToNull(_notesController.text);

    try {
      if (widget.existing == null) {
        await notifier.createSupplier(
          name: name,
          code: code,
          phone: phone,
          email: email,
          address: address,
          notes: notes,
        );
      } else {
        await notifier.updateSupplier(
          supplierId: widget.existing!.id,
          name: name,
          code: code,
          clearCode: code == null,
          phone: phone,
          clearPhone: phone == null,
          email: email,
          clearEmail: email == null,
          address: address,
          clearAddress: address == null,
          notes: notes,
          clearNotes: notes == null,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SupplierException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failureType = error.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failureType = SupplierFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SupplierFailureType? failure = _failureType;

    return AlertDialog(
      title: Text(_isEditMode ? 'تعديل مورد' : 'إضافة مورد'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppTextField(
                  controller: _nameController,
                  label: 'اسم المورد',
                  hint: 'مثال: شركة الأمل للتوريدات',
                  enabled: !_isSubmitting,
                  autofocus: true,
                  validator: _validateName,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _codeController,
                  label: 'الكود — اختياري',
                  hint: 'مثال: SUP-001',
                  enabled: !_isSubmitting,
                  validator: _validateCode,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _phoneController,
                  label: 'الهاتف — اختياري',
                  hint: 'مثال: 01012345678',
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.phone,
                  validator: _validatePhone,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _emailController,
                  label: 'البريد الإلكتروني — اختياري',
                  hint: 'example@domain.com',
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _addressController,
                  label: 'العنوان — اختياري',
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  validator: _validateAddress,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _notesController,
                  label: 'ملاحظات — اختياري',
                  enabled: !_isSubmitting,
                  maxLines: 3,
                  validator: _validateNotes,
                ),
                if (failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _FailureBanner(message: _failureMessage(failure)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'إلغاء',
          variant: AppButtonVariant.text,
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _isEditMode ? 'حفظ' : 'إضافة',
          isLoading: _isSubmitting,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
      backgroundColor: theme.colorScheme.surface,
      scrollable: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Validators
  // ---------------------------------------------------------------------------

  String? _validateName(String? value) {
    final ValidationError? error = Validators.firstError(<ValidationError?>[
      Validators.required(value),
      Validators.minLength(value, 1),
      Validators.maxLength(value, 200),
    ]);
    return error == null ? null : _validationMessage(error);
  }

  String? _validateCode(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 64) {
      return 'الكود طويل جدًا (الحد الأقصى 64 حرفًا)';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 30) {
      return 'رقم الهاتف طويل جدًا (الحد الأقصى 30 حرفًا)';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final ValidationError? error = Validators.email(trimmed);
    return error == null ? null : _validationMessage(error);
  }

  String? _validateAddress(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 500) {
      return 'العنوان طويل جدًا (الحد الأقصى 500 حرف)';
    }
    return null;
  }

  String? _validateNotes(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 2000) {
      return 'الملاحظات طويلة جدًا (الحد الأقصى 2000 حرف)';
    }
    return null;
  }
}

// ============================================================================
// Inline error banner
// ============================================================================

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: scheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Enums
// ============================================================================

enum _SupplierAction { recordPayment, edit, toggleActive, delete }

enum _StatusFilter { all, active, inactive }

enum _SortOption {
  nameAsc,
  nameDesc,
  newest,
  oldest,
  balanceDesc,
  balanceAsc,
}

// ============================================================================
// Localization helpers
// ============================================================================

void _showError(BuildContext context, SupplierException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _errorMessage(Object error) {
  if (error is SupplierException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(SupplierFailureType type) => switch (type) {
      SupplierFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      SupplierFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      SupplierFailureType.notFound =>
        'المورد المطلوب غير موجود أو تم حذفه.',
      SupplierFailureType.nameConflict =>
        'يوجد مورد آخر بنفس الاسم في هذه الشركة.',
      SupplierFailureType.codeConflict =>
        'يوجد مورد آخر بنفس الكود في هذه الشركة.',
      SupplierFailureType.phoneConflict =>
        'يوجد مورد آخر بنفس رقم الهاتف في هذه الشركة.',
      SupplierFailureType.inUse =>
        'لا يمكن حذف المورد لوجود سجلات مرتبطة به. يمكنك تعطيله بدلًا من ذلك.',
      SupplierFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الموردين. يرجى المحاولة لاحقًا.',
      SupplierFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };

String _validationMessage(ValidationError error) => switch (error) {
      ValidationError.required => 'هذا الحقل مطلوب',
      ValidationError.invalidEmail => 'صيغة البريد الإلكتروني غير صحيحة',
      ValidationError.invalidPhone => 'صيغة رقم الهاتف غير صحيحة',
      ValidationError.tooShort => 'القيمة قصيرة جدًا',
      ValidationError.tooLong => 'القيمة طويلة جدًا',
      ValidationError.invalidNumber => 'يجب إدخال رقم صحيح',
      ValidationError.mustBePositive => 'يجب أن تكون القيمة موجبة',
    };
