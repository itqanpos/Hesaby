// lib/features/pos/presentation/widgets/pos_results_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../domain/entities/pos_cart_line.dart';
import '../dialogs/pos_duplicate_line_dialog.dart';
import '../dialogs/pos_unit_quick_add_sheet.dart';
import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';

/// POS search results.
///
/// Two presentations:
/// * **Desktop / tablet** (`compact: false`): grid of cards.
/// * **Mobile** (`compact: true`): linear list without cards, optimised for
///   one-handed search and quick tapping.
class PosResultsList extends ConsumerWidget {
  const PosResultsList({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Product>> results =
        ref.watch(posSearchResultsProvider);
    final PosSearchState search = ref.watch(posSearchProvider);

    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);
    final Map<String, String> unitNames = unitsAsync.maybeWhen(
      data: (List<Unit> units) => <String, String>{
        for (final Unit unit in units) unit.id: unit.name,
      },
      orElse: () => const <String, String>{},
    );

    return results.when(
      loading: () => const AppLoader(),
      error: (Object _, StackTrace __) => AppErrorView(
        title: 'تعذّر تحميل المنتجات',
        message: 'حدث خطأ أثناء تحميل قائمة المنتجات.',
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(productsProvider),
      ),
      data: (List<Product> products) {
        if (products.isEmpty) {
          return AppEmptyView(
            icon: search.isEmpty ? Icons.search : Icons.search_off_outlined,
            title: search.isEmpty ? 'ابحث عن منتج' : 'لا نتائج',
            message: search.isEmpty
                ? 'اكتب اسم المنتج أو الكود أو امسح الباركود.'
                : 'لم يتم العثور على منتج مطابق.',
          );
        }

        if (compact) {
          return _ProductList(
            products: products,
            unitNames: unitNames,
            onTap: (Product p) => _handleProductTap(context, ref, p),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9,
          ),
          itemCount: products.length,
          itemBuilder: (BuildContext context, int index) {
            final Product product = products[index];
            final String? unitName = unitNames[product.defaultUnitId];

            return _ProductGridCard(
              product: product,
              unitName: unitName,
              onTap: () => _handleProductTap(context, ref, product),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tap handling — option ج
  // ---------------------------------------------------------------------------

  Future<void> _handleProductTap(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    List<ProductUnit> extras;
    try {
      extras = await ref.read(productUnitsProvider(product.id).future);
    } on Object {
      if (!context.mounted) return;
      await _openUnitSheet(context, ref, product);
      return;
    }
    if (!context.mounted) return;

    if (extras.isEmpty) {
      await _addDirectly(context, ref, product);
    } else {
      await _openUnitSheet(context, ref, product);
    }
  }

  Future<void> _addDirectly(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final PosCartLine? existing = findExistingCartLine(
      ref.read(posCartProvider),
      product.id,
      product.defaultUnitId,
    );

    // ⬇️ فحص مسبق: إذا كان المنتج موجودًا في السلة وله كمية متاحة،
    //    تأكد من أن الزيادة لن تتجاوزها قبل إظهار نافذة التأكيد.
    final double? availableStock = existing?.availableStock;
    if (availableStock != null) {
      final double currentQty = existing?.quantity ?? 0;
      final double newQty = currentQty + 1;
      if (newQty > availableStock) {
        _show(
          context,
          availableStock <= 0
              ? 'لا يوجد مخزون متاح من «${product.name}».'
              : 'الكمية المتاحة من «${product.name}» هي '
                  '${_formatQty(availableStock)} فقط. '
                  'لديك بالفعل ${_formatQty(currentQty)} في السلة.',
          isError: true,
        );
        return;
      }
    }

    if (existing != null) {
      final bool confirmed = await confirmIncreaseExistingLine(
        context,
        productName: product.name,
        currentQuantity: existing.quantity,
      );
      if (!context.mounted || !confirmed) return;
    }

    final PosQuickAddResult result = posQuickAddProduct(ref, product);
    if (!context.mounted) return;
    switch (result) {
      case PosQuickAddResult.success:
        ref.read(posSearchProvider.notifier).clear();
      case PosQuickAddResult.noBranch:
        _show(context, 'اختر الفرع أولاً قبل إضافة المنتجات.',
            isError: true);
      case PosQuickAddResult.unitsNotLoaded:
        _show(context, 'جاري تحميل بيانات الوحدات، حاول مرة أخرى.',
            isError: true);
      case PosQuickAddResult.noDefaultUnit:
        _show(context, 'تعذّر تحديد الوحدة الافتراضية لهذا المنتج.',
            isError: true);
      case PosQuickAddResult.rejected:
        // ⬇️ حاول إعطاء سبب محدد عند الرفض
        if (availableStock != null) {
          _show(
            context,
            availableStock <= 0
                ? 'لا يوجد مخزون متاح من «${product.name}».'
                : 'الكمية المتاحة من «${product.name}» هي '
                    '${_formatQty(availableStock)} فقط.',
            isError: true,
          );
        } else {
          _show(
            context,
            'تعذّرت إضافة «${product.name}». '
                'قد تكون الكمية غير كافية أو السعر خارج النطاق المسموح.',
            isError: true,
          );
        }
    }
  }

  Future<void> _openUnitSheet(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final bool? added = await showPosUnitQuickAddSheet(
      context: context,
      product: product,
    );
    if (added == true) {
      ref.read(posSearchProvider.notifier).clear();
    }
  }

  void _show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    if (!context.mounted) return;
    final ThemeData theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: isError
                ? TextStyle(color: theme.colorScheme.onError)
                : null,
          ),
          backgroundColor:
              isError ? theme.colorScheme.error : null,
          duration: Duration(seconds: isError ? 5 : 3),
        ),
      );
  }

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

// ============================================================================
// Mobile — linear list (no cards)
// ============================================================================

class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.products,
    required this.unitNames,
    required this.onTap,
  });

  final List<Product> products;
  final Map<String, String> unitNames;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: products.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
      itemBuilder: (BuildContext context, int index) {
        final Product product = products[index];
        final String? unitName = unitNames[product.defaultUnitId];

        return InkWell(
          onTap: () => onTap(product),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        product.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (unitName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            unitName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatPrice(product.sellingPrice)} ج.م',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_left, size: 18, color: scheme.outline),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatPrice(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

// ============================================================================
// Desktop — grid card
// ============================================================================

class _ProductGridCard extends StatefulWidget {
  const _ProductGridCard({
    required this.product,
    required this.unitName,
    required this.onTap,
  });

  final Product product;
  final String? unitName;
  final VoidCallback onTap;

  @override
  State<_ProductGridCard> createState() => _ProductGridCardState();
}

class _ProductGridCardState extends State<_ProductGridCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovered
                ? scheme.primaryContainer.withValues(alpha: 0.3)
                : scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? scheme.primary : scheme.outlineVariant,
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child:
                      Icon(Icons.inventory_2_outlined, color: scheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.product.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.product.sellingPrice} ج.م',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Public quick-add helper
// ============================================================================
PosQuickAddResult posQuickAddProduct(WidgetRef ref, Product product) {
  final CompanyContextState state = ref.read(companyContextProvider);
  final String? branchId = state.currentBranch?.id;
  if (branchId == null) return PosQuickAddResult.noBranch;

  final AsyncValue<List<Unit>> unitsAsync = ref.read(unitsProvider);
  final List<Unit>? units = unitsAsync.valueOrNull;
  if (units == null) return PosQuickAddResult.unitsNotLoaded;

  String? unitName;
  for (final Unit unit in units) {
    if (unit.id == product.defaultUnitId) {
      unitName = unit.name;
      break;
    }
  }
  if (unitName == null) return PosQuickAddResult.noDefaultUnit;

  final bool added = ref.read(posCartProvider.notifier).addLine(
        productId: product.id,
        productName: product.name,
        unitId: product.defaultUnitId,
        unitName: unitName,
        conversionFactor: 1,
        quantity: 1,
        unitPrice: product.sellingPrice,
        minSellingPrice: product.minSellingPrice,
        maxSellingPrice: product.maxSellingPrice,
      );

  if (added) {
    ref.read(focusedCartLineProvider.notifier).state =
        '${product.id}::${product.defaultUnitId}';
    return PosQuickAddResult.success;
  }
  return PosQuickAddResult.rejected;
}

enum PosQuickAddResult {
  success,
  noBranch,
  unitsNotLoaded,
  noDefaultUnit,
  rejected,
}
