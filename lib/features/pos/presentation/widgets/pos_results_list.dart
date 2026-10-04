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
import '../state/pos_providers.dart';
import '../state/pos_search_notifier.dart';
import 'pos_product_result_tile.dart';
import 'pos_unit_selector_sheet.dart';

/// The list of products matching the current POS search query.
///
/// The list is driven entirely by `posSearchResultsProvider`, which
/// combines the query string with the products stream. This widget only
/// resolves unit names once and renders one tile per result.
class PosResultsList extends ConsumerWidget {
  const PosResultsList({super.key});

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
            icon: search.isEmpty
                ? Icons.search
                : Icons.search_off_outlined,
            title: search.isEmpty ? 'ابحث عن منتج' : 'لا نتائج',
            message: search.isEmpty
                ? 'اكتب اسم المنتج أو الكود أو امسح الباركود.'
                : 'لم يتم العثور على منتج مطابق. جرّب كلمات أخرى.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: products.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final Product product = products[index];
            final String? unitName = unitNames[product.defaultUnitId];

            return PosProductResultTile(
              product: product,
              unitName: unitName,
              onTap: () => _handleTap(context, ref, product),
              onQuickAdd: () => _handleQuickAdd(context, ref, product),
            );
          },
        );
      },
    );
  }

  void _handleQuickAdd(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) {
    final CompanyContextState state = ref.read(companyContextProvider);
    final String? branchId = state.currentBranch?.id;
    if (branchId == null) {
      return;
    }

    final AsyncValue<List<Unit>> unitsAsync = ref.read(unitsProvider);
    final String? unitName = unitsAsync.maybeWhen(
      data: (List<Unit> units) {
        for (final Unit unit in units) {
          if (unit.id == product.defaultUnitId) {
            return unit.name;
          }
        }
        return null;
      },
      orElse: () => null,
    );
    if (unitName == null) {
      return;
    }

    ref.read(posCartProvider.notifier).addLine(
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

    ref.read(posSearchProvider.notifier).clear();
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    await showPosUnitSelectorSheet(context: context, product: product);
  }
}
