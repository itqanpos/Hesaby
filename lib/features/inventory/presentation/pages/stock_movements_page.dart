// lib/features/inventory/presentation/pages/stock_movements_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../providers/inventory_providers.dart';

/// Stock movements ledger page.
///
/// Shows the most recent movements of the selected branch, optionally
/// narrowed to a single product.
///
/// Navigation contract:
/// This page may be reached in two ways:
/// * From [InventoryPage] via `context.pushNamed`, passing an `extra` map
///   with `branchId` (required) and `productId` (optional).
/// * Directly via a URL (e.g. deep link) with no `extra`; in that case the
///   branch is taken from the current company context.
class StockMovementsPage extends ConsumerWidget {
  const StockMovementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, String?>? extra = _readExtra(context);
    final String? extraBranchId = extra?['branchId'];
    final String? extraProductId = extra?['productId'];

    final CompanyContextState contextState =
        ref.watch(companyContextProvider);
    final String? branchId = extraBranchId ?? contextState.currentBranch?.id;

    if (branchId == null) {
      return AppShell(
        appBar: AppBar(title: const Text('سجل الحركات')),
        body: const AppEmptyView(
          icon: Icons.store_mall_directory_outlined,
          title: 'لم يتم اختيار فرع',
          message: 'اختر فرعًا من الصفحة الرئيسية لعرض سجل حركاته.',
        ),
      );
    }

    final AsyncValue<List<StockMovement>> movementsAsync =
        ref.watch(stockMovementsProvider(branchId));
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);

    final bool anyLoading =
        movementsAsync.isLoading || productsAsync.isLoading;
    final Object? firstError = movementsAsync.error ?? productsAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('سجل الحركات'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: anyLoading
                ? null
                : () => ref
                    .read(stockMovementsProvider(branchId).notifier)
                    .refresh(),
            icon: const Icon(Icons.refresh),
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
              title: 'تعذّر تحميل سجل الحركات',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(stockMovementsProvider(branchId));
                ref.invalidate(productsProvider);
              },
            );
          }

          final List<StockMovement> allMovements =
              movementsAsync.value ?? const <StockMovement>[];
          final List<Product> products =
              productsAsync.value ?? const <Product>[];

          final Map<String, Product> productsById = <String, Product>{
            for (final Product product in products) product.id: product,
          };

          final List<StockMovement> movements = extraProductId == null
              ? allMovements
              : allMovements
                  .where((StockMovement m) => m.productId == extraProductId)
                  .toList(growable: false);

          if (movements.isEmpty) {
            return AppEmptyView(
              icon: Icons.history,
              title: 'لا توجد حركات',
              message: extraProductId == null
                  ? 'لم تُسجَّل أي حركة مخزون في هذا الفرع بعد.'
                  : 'لم تُسجَّل أي حركة لهذا المنتج في هذا الفرع بعد.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: movements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final StockMovement movement = movements[index];
              final Product? product = productsById[movement.productId];

              return _MovementCard(
                movement: movement,
                productName: product?.name ?? 'منتج محذوف',
              );
            },
          );
        },
      ),
    );
  }

  /// Reads the `extra` value passed by the router, when present.
  ///
  /// Uses the current `GoRouterState` so the page does not depend on
  /// constructor parameters. Returns `null` when no `extra` was supplied or
  /// when the value is not a `Map<String, String?>`.
  static Map<String, String?>? _readExtra(BuildContext context) {
    final GoRouterState state = GoRouterState.of(context);
    final Object? extra = state.extra;
    if (extra is Map<String, String?>) {
      return extra;
    }
    if (extra is Map) {
      // Defensive: accept any `Map` whose keys are strings and whose values
      // are strings or null. This keeps the page robust when a caller
      // constructs the extra with a more specific Map subtype.
      final Map<String, String?> casted = <String, String?>{};
      for (final MapEntry<Object?, Object?> entry in extra.entries) {
        final Object? key = entry.key;
        final Object? value = entry.value;
        if (key is String && (value == null || value is String)) {
          casted[key] = value as String?;
        }
      }
      return casted.isEmpty ? null : casted;
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// Movement card
// -----------------------------------------------------------------------------

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.movement,
    required this.productName,
  });

  final StockMovement movement;
  final String productName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isIncrease = movement.isIncrease;

    final Color accent = isIncrease ? scheme.primary : scheme.error;

    final NumberFormat numberFormat = NumberFormat.decimalPattern('ar_EG');
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    final DateFormat dateTimeFormat = DateFormat.yMd('ar_EG').add_Hm();

    final String quantityLabel =
        '${isIncrease ? '+' : '-'}'
        '${numberFormat.format(movement.absoluteQuantity)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isIncrease
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    productName,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  quantityLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _MetaChip(label: _movementTypeLabel(movement.movementType)),
                Text(
                  dateTimeFormat.format(movement.createdAt.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
                if (movement.hasUnitCost)
                  Text(
                    'تكلفة: ${moneyFormat.format(movement.unitCost!)}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (movement.hasNotes) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                movement.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Localization helpers
// -----------------------------------------------------------------------------

String _movementTypeLabel(String type) => switch (type) {
      StockMovementType.adjustmentIn => 'تسوية إدخال',
      StockMovementType.adjustmentOut => 'تسوية إخراج',
      StockMovementType.purchaseIn => 'شراء',
      StockMovementType.saleOut => 'بيع',
      StockMovementType.transferIn => 'تحويل وارد',
      StockMovementType.transferOut => 'تحويل صادر',
      StockMovementType.returnIn => 'مرتجع وارد',
      StockMovementType.returnOut => 'مرتجع صادر',
      StockMovementType.openingBalance => 'رصيد افتتاحي',
      _ => 'حركة',
    };

String _errorMessage(Object error) {
  if (error is InventoryException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(InventoryFailureType type) => switch (type) {
      InventoryFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      InventoryFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      InventoryFailureType.notFound =>
        'السجل المطلوب غير موجود أو تم حذفه.',
      InventoryFailureType.insufficientStock =>
        'الرصيد غير كافٍ.',
      InventoryFailureType.productNotFound => 'المنتج المختار غير متاح.',
      InventoryFailureType.branchNotFound => 'الفرع المختار غير متاح.',
      InventoryFailureType.invalidMovementType => 'نوع الحركة غير معروف.',
      InventoryFailureType.invalidMovement =>
        'بيانات الحركة غير صحيحة.',
      InventoryFailureType.invalidResponse =>
        'تعذّر قراءة سجل الحركات. يرجى المحاولة لاحقًا.',
      InventoryFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };
