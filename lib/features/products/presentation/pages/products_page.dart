// lib/features/products/presentation/pages/products_page.dart

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
/// 1. KPI row (total / active / inactive).
/// 2. Search field (name / SKU / barcode).
/// 3. Status chips + Category dropdown + Sort dropdown.
/// 4. Product list (rich card with meta and price info).
///
/// All filtering and sorting are local. Loading is currently eager — a
/// paginated data layer will replace it in a follow-up step without
/// changing this page's structure.
class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  _StatusFilter _statusFilter = _StatusFilter.all;
  String? _categoryFilterId;
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
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);
    final AsyncValue<List<ProductCategory>> categoriesAsync =
        ref.watch(categoriesProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    final bool anyLoading = productsAsync.isLoading ||
        categoriesAsync.isLoading ||
        unitsAsync.isLoading;
    final Object? firstError =
        productsAsync.error ?? categoriesAsync.error ?? unitsAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('المنتجات'),
        actions: <Widget>[
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
              title: 'تعذّر تحميل المنتجات',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(productsProvider);
                ref.invalidate(categoriesProvider);
                ref.invalidate(unitsProvider);
              },
            );
          }

          final List<Product> allProducts =
              productsAsync.value ?? const <Product>[];
          final List<ProductCategory> categories =
              categoriesAsync.value ?? const <ProductCategory>[];
          final List<Unit> units = unitsAsync.value ?? const <Unit>[];

          // Fast lookups by id.
          final Map<String, String> categoryNames = <String, String>{
            for (final ProductCategory category in categories)
              category.id: category.name,
          };
          final Map<String, String> unitNames = <String, String>{
            for (final Unit unit in units) unit.id: unit.name,
          };

          final List<Product> visible = _applyFiltersAndSort(allProducts);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- KPI row ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _KpiRow(products: allProducts),
              ),

              // ---- Search ----
              AppTextField(
                controller: _searchController,
                hint: 'ابحث بالاسم أو SKU أو الباركود',
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

              // ---- Status + Category + Sort ----
              _FilterBar(
                status: _statusFilter,
                categoryId: _categoryFilterId,
                sort: _sort,
                categories: categories,
                onStatusChanged: (v) => setState(() => _statusFilter = v),
                onCategoryChanged: (v) =>
                    setState(() => _categoryFilterId = v),
                onSortChanged: (v) => setState(() => _sort = v),
              ),

              const SizedBox(height: 8),

              // ---- List ----
              Expanded(
                child: Builder(
                  builder: (BuildContext context) {
                    if (allProducts.isEmpty) {
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
                                onPressed: () => _openProductForm(context),
                              ),
                      );
                    }

                    if (visible.isEmpty) {
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

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final Product product = visible[index];
                        return _ProductCard(
                          product: product,
                          categoryName: product.categoryId == null
                              ? null
                              : categoryNames[product.categoryId],
                          unitName: unitNames[product.defaultUnitId],
                          onEdit: () =>
                              _openProductForm(context, product: product),
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
  // Filtering + sorting
  // ---------------------------------------------------------------------------

  List<Product> _applyFiltersAndSort(List<Product> products) {
    final String trimmed = _searchQuery.trim().toLowerCase();

    Iterable<Product> result = products;

    // ---- Status filter ----
    switch (_statusFilter) {
      case _StatusFilter.all:
        break;
      case _StatusFilter.active:
        result = result.where((p) => p.isActive);
      case _StatusFilter.inactive:
        result = result.where((p) => !p.isActive);
    }

    // ---- Category filter ----
    if (_categoryFilterId != null) {
      result = result.where((p) => p.categoryId == _categoryFilterId);
    }

    // ---- Search ----
    if (trimmed.isNotEmpty) {
      result = result.where((Product product) {
        final String name = product.name.toLowerCase();
        final String sku = (product.sku ?? '').toLowerCase();
        final String barcode = (product.barcode ?? '').toLowerCase();
        return name.contains(trimmed) ||
            sku.contains(trimmed) ||
            barcode.contains(trimmed);
      });
    }

    // ---- Sort ----
    final List<Product> list = result.toList(growable: false);
    switch (_sort) {
      case _SortOption.nameAsc:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _SortOption.nameDesc:
        list.sort((a, b) => b.name.compareTo(a.name));
      case _SortOption.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _SortOption.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _SortOption.sellingAsc:
        list.sort((a, b) => a.sellingPrice.compareTo(b.sellingPrice));
      case _SortOption.sellingDesc:
        list.sort((a, b) => b.sellingPrice.compareTo(a.sellingPrice));
      case _SortOption.costAsc:
        list.sort((a, b) => a.costPrice.compareTo(b.costPrice));
      case _SortOption.costDesc:
        list.sort((a, b) => b.costPrice.compareTo(a.costPrice));
    }

    return list;
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _statusFilter = _StatusFilter.all;
      _categoryFilterId = null;
      _sort = _SortOption.nameAsc;
    });
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
  const _KpiRow({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    int active = 0;
    int inactive = 0;
    for (final Product p in products) {
      if (p.isActive) {
        active++;
      } else {
        inactive++;
      }
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: _KpiCard(
            icon: Icons.inventory_2_outlined,
            label: 'الإجمالي',
            value: products.length.toString(),
            color: const Color(0xFF0288D1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.check_circle_outline,
            label: 'نشط',
            value: active.toString(),
            color: const Color(0xFF0F7B6C),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            icon: Icons.pause_circle_outline,
            label: 'معطّل',
            value: inactive.toString(),
            color: const Color(0xFF7B5E3A),
            emphasize: inactive > 0,
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

// ============================================================================
// Filter bar (status + category + sort)
// ============================================================================

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.categoryId,
    required this.sort,
    required this.categories,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onSortChanged,
  });

  final _StatusFilter status;
  final String? categoryId;
  final _SortOption sort;
  final List<ProductCategory> categories;
  final ValueChanged<_StatusFilter> onStatusChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<_SortOption> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          // Status chips
          for (final _StatusFilter option in _StatusFilter.values) ...<Widget>[
            ChoiceChip(
              label: Text(_statusLabel(option)),
              selected: status == option,
              onSelected: (_) => onStatusChanged(option),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
          ],

          const SizedBox(width: 4),

          // Category dropdown
          _CategoryChip(
            categories: categories,
            selectedId: categoryId,
            onChanged: onCategoryChanged,
          ),

          const SizedBox(width: 6),

          // Sort dropdown
          _SortChip(
            sort: sort,
            onChanged: onSortChanged,
          ),
        ],
      ),
    );
  }

  static String _statusLabel(_StatusFilter filter) {
    switch (filter) {
      case _StatusFilter.all:
        return 'الكل';
      case _StatusFilter.active:
        return 'نشط';
      case _StatusFilter.inactive:
        return 'معطّل';
    }
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
        backgroundColor:
            hasSelection ? Theme.of(context).colorScheme.primaryContainer : null,
        visualDensity: VisualDensity.compact,
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
      case _SortOption.nameAsc:
        return 'الاسم (أ-ي)';
      case _SortOption.nameDesc:
        return 'الاسم (ي-أ)';
      case _SortOption.newest:
        return 'الأحدث';
      case _SortOption.oldest:
        return 'الأقدم';
      case _SortOption.sellingAsc:
        return 'سعر البيع ↑';
      case _SortOption.sellingDesc:
        return 'سعر البيع ↓';
      case _SortOption.costAsc:
        return 'التكلفة ↑';
      case _SortOption.costDesc:
        return 'التكلفة ↓';
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
              // ---- Leading avatar ----
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

              // ---- Main content ----
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Name + status badge
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

                    // SKU + Barcode (only if present)
                    if (product.hasSku || product.hasBarcode) ...<Widget>[
                      const SizedBox(height: 3),
                      _CodeLine(product: product),
                    ],

                    // Category + unit badges
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

                    // Price row
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

              // ---- Actions ----
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
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        letterSpacing: 0.2,
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

enum _StatusFilter { all, active, inactive }

enum _SortOption {
  nameAsc,
  nameDesc,
  newest,
  oldest,
  sellingAsc,
  sellingDesc,
  costAsc,
  costDesc,
}

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
