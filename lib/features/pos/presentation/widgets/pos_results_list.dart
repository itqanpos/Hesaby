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
import 'pos_product_result_tile.dart';

/// The list of products matching the current POS search query.
///
/// Each tile shows the product name and its **default-unit** price and
/// stock. Tapping a tile opens `showPosUnitQuickAddSheet`, where the
/// cashier picks the unit to add to the cart.
///
/// After a successful add, the search query is cleared automatically so the
/// cashier is immediately ready to look up the next product.
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
                : 'لم يتم العثور على منتج مطابق. '
                    'جرّب كلمات أخرى أو تحقق من الكتالوج.',
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
              onTap: () => _openUnitSheet(context, ref, product),
            );
          },
        );
      },
    );
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

    if (added != true) {
      return;
    }

    // Clear the search query so the results area empties and the cart
    // regains the full middle area — ready for the next scan.
    ref.read(posSearchProvider.notifier).clear();
  }
}

// ============================================================================
// Public quick-add helper
// ============================================================================

/// Adds [product] to the POS cart at its default unit and catalogue price,
/// with quantity 1.
///
/// Used by the barcode-scanning flow when exactly one product matches the
/// scanned value.
bool posQuickAddProduct(WidgetRef ref, Product product) {
  final CompanyContextState state = ref.read(companyContextProvider);
  final String? branchId = state.currentBranch?.id;
  if (branchId == null) {
    return false;
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
    return false;
  }

  return ref.read(posCartProvider.notifier).addLine(
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
}
