// lib/features/pos/presentation/widgets/pos_results_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../dialogs/pos_unit_quick_add_sheet.dart';
import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';

class PosResultsList extends ConsumerWidget {
  const PosResultsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Product>> results = ref.watch(posSearchResultsProvider);
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

        // ⬇️ تحويل القائمة إلى GridView
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160, // أقصى عرض للبطاقة
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9, // نسبة الطول للعرض
          ),
          itemCount: products.length,
          itemBuilder: (BuildContext context, int index) {
            final Product product = products[index];
            final String? unitName = unitNames[product.defaultUnitId];

            return _ProductGridCard(
              product: product,
              unitName: unitName,
              onTap: () => _openUnitSheet(context, ref, product),
            );
          },
        );
      },
    );
  }

  Future<void> _openUnitSheet(BuildContext context, WidgetRef ref, Product product) async {
    final bool? added = await showPosUnitQuickAddSheet(context: context, product: product);
    if (added == true) {
      ref.read(posSearchProvider.notifier).clear();
    }
  }
}

// ⬇️ بطاقة المنتج الجديدة (شبكة)
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
            color: _isHovered ? scheme.primaryContainer.withValues(alpha: 0.3) : scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? scheme.primary : scheme.outlineVariant,
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: _isHovered
                ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // أيقونة وهمية (لعدم وجود صور)
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Icon(Icons.inventory_2_outlined, color: scheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.product.name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
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
// Public quick-add helper (بدون تغيير)
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
    ref.read(focusedCartLineProvider.notifier).state = '${product.id}::${product.defaultUnitId}';
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
