// lib/features/products/presentation/pages/products_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/unit.dart';
import '../../domain/repositories/product_repository.dart';
import '../providers/category_providers.dart';
import '../providers/product_providers.dart';
import '../providers/unit_providers.dart';
import 'product_form_dialog.dart';
import 'product_units_dialog.dart';

/// Product management page.
///
/// Layout (top → bottom):
/// 1. KPI row (total / active / inactive) — global for the whole company.
/// 2. Search field (debounced, server-side).
/// 3. Status chips + Category dropdown + Sort dropdown — server-side.
/// 4. Paginated product list (20 items per page, auto-loads on scroll).
class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Scroll → load more
  // ---------------------------------------------------------------------------

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double threshold =
        _scrollController.position.maxScrollExtent * 0.85;
    if (_scrollController.position.pixels >= threshold) {
      // Fire-and-forget; the notifier guards against concurrent calls.
      unawaited(ref.read(pagedProductsProvider.notifier).loadMore());
    }
  }

  // ---------------------------------------------------------------------------
  // Search — debounced
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.read(productsFilterProvider.notifier).setSearch(value);
      _jumpToTop();
    });
  }

  void _jumpToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _clearAllFilters() {
    _searchController.clear();
    ref.read(productsFilterProvider.notifier).clearAll();
    _jumpToTop();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ProductCounts> countsAsync =
        ref.watch(productCountsProvider);
    final AsyncValue<List<ProductCategory>> categoriesAsync =
        ref.watch(categoriesProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);
    final AsyncValue<PagedProducts> pagedAsync =
        ref.watch(pagedProductsProvider);
    final ProductsFilter filter = ref.watch(productsFilterProvider);

    final bool anyLoading = categoriesAsync.isLoading || unitsAsync.isLoading;
    final Object? firstError =
        categoriesAsync.error ?? unitsAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('المنتجات'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: () {
              ref.invalidate(productCountsProvider);
              ref.read(pagedProductsProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'إضافة منتج',
            onPressed: anyLoading || firstError != null
                ? null
                : () => _openProductForm(context),
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
              title: 'تعذّر تحميل البيانات الأساسية',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(categoriesProvider);
                ref.invalidate(unitsProvider);
              },
            );
          }

          final List<ProductCategory> categories =
              categoriesAsync.value ?? const <ProductCategory>[];
          final List<Unit> units = unitsAsync.value ?? const <Unit>[];

          // Fast lookups from id → display name.
          final Map<String, String> categoryNames = <String, String>{
            for (final ProductCategory category in categories)
              category.id: category.name,
          };
          final Map<String, String> unitNames = <String, String>{
            for (final Unit unit in units) unit.id: unit.name,
          };

          final bool hasActiveFilters =
              filter.searchQuery.trim().isNotEmpty ||
                  filter.categoryId != null ||
                  filter.isActive != null ||
                  filter.sortField != ProductSortField.name ||
                  !filter.sortAscending;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- KPI ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _KpiRow(
                  counts: countsAsync.valueOrNull ??
                      const ProductCounts.zero(),
                  isLoading: countsAsync.isLoading,
                  activeFilter: filter.isActive,
                  onStatusTap: (bool? status) {
                    ref.read(productsFilterProvider.notifier).setStatus(status);
                    _jumpToTop();
                  },
                ),
              ),

              // ---- Search ----
              AppTextField(
                controller: _searchController,
                hint: 'ابحث بالاسم أو SKU أو الباركود',
                prefixIcon: Icons.search,
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _searchDebounce?.cancel();
                          ref
                              .read(productsFilterProvider.notifier)
                              .setSearch('');
                          _jumpToTop();
                        },
                      ),
                onChanged: _onSearchChanged,
              ),

              const SizedBox(height: 10),

              // ---- Filters ----
              _FilterBar(
                filter: filter,
                categories: categories,
                onStatusChanged: (bool? v) {
                  ref.read(productsFilterProvider.notifier).setStatus(v);
                  _jumpToTop();
                },
                onCategoryChanged: (String? v) {
                  ref.read(productsFilterProvider.notifier).setCategory(v);
                  _jumpToTop();
                },
                onSortChanged: (ProductSortField f, bool asc) {
                  ref
                      .read(productsFilterProvider.notifier)
                      .setSort(f, ascending: asc);
                  _jumpToTop();
                },
              ),

              const SizedBox(height: 8),

              // ---- List ----
              Expanded(
                child: Builder(
                  builder: (BuildContext context) {
                    final PagedProducts? paged = pagedAsync.valueOrNull;
                    final bool isInitialLoad =
                        pagedAsync.isLoading && (paged?.items.isEmpty ?? true);
                    final Object? pagedError = pagedAsync.error;

                    if (isInitialLoad) {
                      return const AppLoader();
                    }

                    if (pagedError != null &&
                        (paged?.items.isEmpty ?? true)) {
                      return AppErrorView(
                        title: 'تعذّر تحميل المنتجات',
                        message: _errorMessage(pagedError),
                        retryLabel: 'إعادة المحاولة',
                        onRetry: () => ref
                            .read(pagedProductsProvider.notifier)
                            .refresh(),
                      );
                    }

                    final List<Product> items =
                        paged?.items ?? const <Product>[];

                    if (items.isEmpty) {
                      if (hasActiveFilters) {
                        return AppEmptyView(
                          icon: Icons.search_off_outlined,
                          title: 'لا نتائج',
                          message:
                              'لم يُطابق أي منتج الفلاتر أو كلمة البحث.',
                          action: AppButton(
                            label: 'مسح الفلاتر',
                            icon: Icons.filter_alt_off_outlined,
                            variant: AppButtonVariant.secondary,
                            onPressed: _clearAllFilters,
                          ),
                        );
                      }
                      return AppEmptyView(
                        icon: Icons.inventory_2_outlined,
                        title: 'لا توجد منتجات',
                        message: units.isEmpty
                            ? 'أضف وحدة قياس واحدة على الأقل قبل إنشاء المنتجات.'
                            : 'ابدأ بإضافة أول منتج إلى كتالوجك.',
                        action: units.isEmpty
                            ? null
                            : AppButton(
                                label: 'إضافة منتج',
                                icon: Icons.add,
                                onPressed: () =>
                                    _openProductForm(context),
                              ),
                      );
                    }

                    final bool showLoader = paged?.isLoadingMore ?? false;

                    return ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: items.length + (showLoader ? 1 : 0),
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        if (index >= items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        final Product product = items[index];
                        return _ProductCard(
                          product: product,
                          categoryName: product.categoryId == null
                              ? null
                              : categoryNames[product.categoryId],
                          unitName: unitNames[product.defaultUnitId],
                          onEdit: () => _openProductForm(
                            context,
                            product: product,
                          ),
                          onToggleActive: () =>
                              _toggleActive(context, product),
                          onDelete: () => _confirmDelete(context, product),
                          onManageUnits: () =>
                              _openProductUnits(context, product),
                        );
                      },
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

  Future<void> _openProductForm(
    BuildContext context, {
    Product? product,
  }) async {
    final bool? saved = await showProductFormDialog(
      context: context,
      existing: product,
    );

    if (!context.mounted || saved != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(product == null ? 'تم إضافة المنتج' : 'تم تحديث المنتج'),
      ),
    );
  }

  Future<void> _openProductUnits(
    BuildContext context,
    Product product,
  ) async {
    await showProductUnitsDialog(
      context: context,
      product: product,
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    Product product,
  ) async {
    try {
      await ref.read(productsProvider.notifier).updateProduct(
            productId: product.id,
            isActive: !product.isActive,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product.isActive ? 'تم تعطيل المنتج' : 'تم تفعيل المنتج',
          ),
        ),
      );
    } on ProductException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Product product,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: Text(
          'هل تريد حذف "${product.name}"؟ سيتم حذف كل تحويلات الوحدات '
          'المرتبطة به. لا يمكن التراجع عن هذا الإجراء.',
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

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref.read(productsProvider.notifier).deleteProduct(product.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المنتج')),
      );
    } on ProductException catch (error) {
      if (!context.mounted) {
        return;
      }
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
    required this.activeFilter,
    required this.onStatusTap,
  });

  final ProductCounts counts;
  final bool isLoading;
  final bool? activeFilter;
  final ValueChanged<bool?> onStatusTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            icon: Icons.inventory_2_outlined,
            label: 'الإجمالي',
            value: isLoading ? '…' : counts.total.toString(),
            color: const Color(0xFF0288D1),
            selected: activeFilter == null,
            onTap: () => onStatusTap(null),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.check_circle_outline,
            label: 'نشط',
            value: isLoading ? '…' : counts.active.toString(),
            color: const Color(0xFF0F7B6C),
            selected: activeFilter == true,
            onTap: () => onStatusTap(true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.pause_circle_outline,
            label: 'معطّل',
            value: isLoading ? '…' : counts.inactive.toString(),
            color: const Color(0xFF7B5E3A),
            selected: activeFilter == false,
            onTap: () => onStatusTap(false),
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
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool selected;
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
              color: selected ? color : scheme.outlineVariant,
              width: selected ? 1.8 : 1,
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
                  color: selected ? color : scheme.onSurface,
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
    required this.filter,
    required this.categories,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onSortChanged,
  });

  final ProductsFilter filter;
  final List<ProductCategory> categories;
  final ValueChanged<bool?> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final void Function(ProductSortField field, bool ascending) onSortChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('الكل'),
            selected: filter.isActive == null,
            onSelected: (_) => onStatusChanged(null),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('نشط'),
            selected: filter.isActive == true,
            onSelected: (_) => onStatusChanged(true),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('معطّل'),
            selected: filter.isActive == false,
            onSelected: (_) => onStatusChanged(false),
            visualDensity: VisualDensity.compact,
          ),

          const SizedBox(width: 8),

          _CategoryChip(
            categories: categories,
            selectedId: filter.categoryId,
            onChanged: onCategoryChanged,
          ),

          const SizedBox(width: 6),

          _SortChip(
            field: filter.sortField,
            ascending: filter.sortAscending,
            onChanged: onSortChanged,
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
  });

  final List<ProductCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool hasSelection = selectedId != null;
    final String label = hasSelection
        ? categories.firstWhere((c) => c.id == selectedId).name
        : 'التصنيف';

    return PopupMenuButton<String?>(
      tooltip: 'اختر تصنيفًا',
      onSelected: onChanged,
      itemBuilder: (BuildContext _) => <PopupMenuEntry<String?>>[
        const PopupMenuItem<String?>(
          value: null,
          child: Text('كل التصنيفات'),
        ),
        const PopupMenuDivider(),
        for (final ProductCategory c in categories)
          PopupMenuItem<String?>(
            value: c.id,
            child: Text(c.name),
          ),
      ],
      child: Chip(
        avatar: Icon(
          hasSelection ? Icons.filter_alt : Icons.category_outlined,
          size: 16,
        ),
        label: Text(label),
        backgroundColor: hasSelection
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.field,
    required this.ascending,
    required this.onChanged,
  });

  final ProductSortField field;
  final bool ascending;
  final void Function(ProductSortField field, bool ascending) onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'ترتيب',
      onSelected: (String value) {
        final List<String> parts = value.split('|');
        final ProductSortField field =
            ProductSortField.values.firstWhere((f) => f.name == parts[0]);
        final bool asc = parts[1] == 'asc';
        onChanged(field, asc);
      },
      itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
        for (final ProductSortField f in ProductSortField.values) ...<PopupMenuEntry<String>>[
          CheckedPopupMenuItem<String>(
            value: '${f.name}|asc',
            checked: field == f && ascending,
            child: Text('${_fieldLabel(f)} ↑'),
          ),
          CheckedPopupMenuItem<String>(
            value: '${f.name}|desc',
            checked: field == f && !ascending,
            child: Text('${_fieldLabel(f)} ↓'),
          ),
        ],
      ],
      child: Chip(
        avatar: const Icon(Icons.sort, size: 16),
        label: Text('${_fieldLabel(field)} ${ascending ? "↑" : "↓"}'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  static String _fieldLabel(ProductSortField f) {
    switch (f) {
      case ProductSortField.name:
        return 'الاسم';
      case ProductSortField.sellingPrice:
        return 'سعر البيع';
      case ProductSortField.costPrice:
        return 'التكلفة';
      case ProductSortField.createdAt:
        return 'تاريخ الإضافة';
    }
  }
}

// ============================================================================
// Product card
// ============================================================================

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.categoryName,
    required this.unitName,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
    required this.onManageUnits,
  });

  final Product product;
  final String? categoryName;
  final String? unitName;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;
  final VoidCallback onManageUnits;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isActive = product.isActive;
    final NumberFormat priceFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

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
                child: Text(
                  product.name.characters.first.toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
                            product.name,
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
                    if (product.hasSku || product.hasBarcode) ...<Widget>[
                      const SizedBox(height: 3),
                      _CodeLine(product: product),
                    ],
                    if (categoryName != null || unitName != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: <Widget>[
                          if (categoryName != null)
                            _Badge(
                              icon: Icons.category_outlined,
                              label: categoryName!,
                              background: scheme.tertiaryContainer,
                              foreground: scheme.onTertiaryContainer,
                            ),
                          if (unitName != null)
                            _Badge(
                              icon: Icons.straighten_outlined,
                              label: unitName!,
                              background: scheme.secondaryContainer,
                              foreground: scheme.onSecondaryContainer,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          priceFormat.format(product.sellingPrice),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'تكلفة: ${priceFormat.format(product.costPrice)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_ProductAction>(
                tooltip: 'خيارات',
                onSelected: (_ProductAction action) {
                  switch (action) {
                    case _ProductAction.edit:
                      onEdit();
                    case _ProductAction.manageUnits:
                      onManageUnits();
                    case _ProductAction.toggleActive:
                      onToggleActive();
                    case _ProductAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_ProductAction>>[
                  const PopupMenuItem<_ProductAction>(
                    value: _ProductAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('تعديل'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<_ProductAction>(
                    value: _ProductAction.manageUnits,
                    child: ListTile(
                      leading: Icon(Icons.swap_horiz_outlined),
                      title: Text('وحدات إضافية'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_ProductAction>(
                    value: _ProductAction.toggleActive,
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
                  const PopupMenuItem<_ProductAction>(
                    value: _ProductAction.delete,
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

// -----------------------------------------------------------------------------
// Small pieces
// -----------------------------------------------------------------------------

class _CodeLine extends StatelessWidget {
  const _CodeLine({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final List<String> parts = <String>[];
    if (product.hasSku) {
      parts.add('SKU: ${product.sku}');
    }
    if (product.hasBarcode) {
      parts.add('Barcode: ${product.barcode}');
    }

    return Text(
      parts.join('  ·  '),
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
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
// Enums
// ============================================================================

enum _ProductAction { edit, manageUnits, toggleActive, delete }

// ============================================================================
// Localization helpers
// ============================================================================

String _errorMessage(Object error) {
  if (error is ProductException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

void _showError(BuildContext context, ProductException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _failureMessage(ProductFailureType type) => switch (type) {
      ProductFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      ProductFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      ProductFailureType.notFound =>
        'المنتج المطلوب غير موجود أو تم حذفه.',
      ProductFailureType.skuConflict =>
        'يوجد منتج آخر بنفس الـ SKU في هذه الشركة.',
      ProductFailureType.barcodeConflict =>
        'يوجد منتج آخر بنفس الباركود في هذه الشركة.',
      ProductFailureType.categoryNotFound =>
        'التصنيف المختار غير متاح. يرجى إعادة اختياره.',
      ProductFailureType.unitNotFound =>
        'وحدة القياس المختارة غير متاحة. يرجى إعادة اختيارها.',
      ProductFailureType.inUse =>
        'لا يمكن حذف المنتج لوجود سجلات مرتبطة به. يمكنك تعطيله بدلًا من ذلك.',
      ProductFailureType.invalidResponse =>
        'تعذّر قراءة بيانات المنتجات. يرجى المحاولة لاحقًا.',
      ProductFailureType.unknown =>
        'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.',
    };
