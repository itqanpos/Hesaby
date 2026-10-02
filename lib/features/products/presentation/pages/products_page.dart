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
/// Displays the products of the currently selected company, with a
/// client-side search across name, SKU and barcode. All mutations are
/// routed through [ProductsNotifier], which delegates to the repository and
/// therefore to Row Level Security in the database.
class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Product>> productsAsync = ref.watch(productsProvider);
    final AsyncValue<List<ProductCategory>> categoriesAsync =
        ref.watch(categoriesProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    final bool anyLoading =
        productsAsync.isLoading || categoriesAsync.isLoading || unitsAsync.isLoading;
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

          // Fast lookups from id -> display name.
          final Map<String, String> categoryNames = <String, String>{
            for (final ProductCategory category in categories)
              category.id: category.name,
          };
          final Map<String, String> unitNames = <String, String>{
            for (final Unit unit in units) unit.id: unit.name,
          };

          final List<Product> filtered = _filter(allProducts, _searchQuery);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: AppTextField(
                  controller: _searchController,
                  hint: 'ابحث بالاسم أو SKU أو الباركود',
                  prefixIcon: Icons.search,
                  onChanged: (String value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
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

                    if (filtered.isEmpty) {
                      return AppEmptyView(
                        icon: Icons.search_off_outlined,
                        title: 'لا نتائج',
                        message: 'لم يُطابق أي منتج كلمة البحث.',
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final Product product = filtered[index];
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
  // Search
  // ---------------------------------------------------------------------------

  List<Product> _filter(List<Product> products, String query) {
    final String trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return products;
    }
    return products.where((Product product) {
      final String name = product.name.toLowerCase();
      final String sku = (product.sku ?? '').toLowerCase();
      final String barcode = (product.barcode ?? '').toLowerCase();
      return name.contains(trimmed) ||
          sku.contains(trimmed) ||
          barcode.contains(trimmed);
    }).toList(growable: false);
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
      ref: ref,
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
      ref: ref,
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

// -----------------------------------------------------------------------------
// Product card
// -----------------------------------------------------------------------------

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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: isActive
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                foregroundColor: isActive
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                child: Text(
                  product.name.characters.first.toUpperCase(),
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
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'معطّل',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _MetaLine(
                      product: product,
                      categoryName: categoryName,
                      unitName: unitName,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Text(
                          priceFormat.format(product.sellingPrice),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'التكلفة: ${priceFormat.format(product.costPrice)}',
                          style: theme.textTheme.bodySmall,
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

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.product,
    required this.categoryName,
    required this.unitName,
  });

  final Product product;
  final String? categoryName;
  final String? unitName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.bodySmall;

    final List<String> parts = <String>[];
    final String? sku = product.sku;
    if (sku != null && sku.isNotEmpty) {
      parts.add('SKU: $sku');
    }
    final String? barcode = product.barcode;
    if (barcode != null && barcode.isNotEmpty) {
      parts.add('Barcode: $barcode');
    }
    if (categoryName != null) {
      parts.add(categoryName!);
    }
    if (unitName != null) {
      parts.add(unitName!);
    }

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      parts.join(' · '),
      style: style,
      overflow: TextOverflow.ellipsis,
    );
  }
}

enum _ProductAction { edit, manageUnits, toggleActive, delete }

// -----------------------------------------------------------------------------
// Localization helpers
// -----------------------------------------------------------------------------

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
