// lib/features/inventory/presentation/pages/stock_movements_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

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
class StockMovementsPage extends ConsumerStatefulWidget {
  const StockMovementsPage({super.key});

  @override
  ConsumerState<StockMovementsPage> createState() => _StockMovementsPageState();
}

class _StockMovementsPageState extends ConsumerState<StockMovementsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterType = 'all'; // 'all', 'in', 'out'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String?>? extra = _readExtra(context);
    final String? extraBranchId = extra?['branchId'];
    final String? extraProductId = extra?['productId'];

    final CompanyContextState contextState = ref.watch(companyContextProvider);
    final String? branchId = extraBranchId ?? contextState.currentBranch?.id;

    if (branchId == null) {
      return AppShell(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('سجل الحركات'),
        ),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
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

          // 1. Filter by extraProductId if passed
          List<StockMovement> movements = extraProductId == null
              ? allMovements
              : allMovements
                  .where((StockMovement m) => m.productId == extraProductId)
                  .toList(growable: false);

          // 2. Apply Search
          if (_searchQuery.isNotEmpty) {
            final String query = _searchQuery.toLowerCase();
            movements = movements.where((StockMovement m) {
              final String pName = productsById[m.productId]?.name.toLowerCase() ?? '';
              return pName.contains(query);
            }).toList(growable: false);
          }

          // 3. Apply Type Filter
          if (_filterType == 'in') {
            movements = movements.where((StockMovement m) => m.isIncrease).toList(growable: false);
          } else if (_filterType == 'out') {
            movements = movements.where((StockMovement m) => !m.isIncrease).toList(growable: false);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SearchAndFilters(
                searchController: _searchController,
                searchQuery: _searchQuery,
                filterType: _filterType,
                onSearchChanged: (String v) => setState(() => _searchQuery = v),
                onClearSearch: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                onFilterChanged: (String v) => setState(() => _filterType = v),
              ),
              Expanded(
                child: movements.isEmpty
                    ? AppEmptyView(
                        icon: Icons.history,
                        title: 'لا توجد حركات',
                        message: _searchQuery.isNotEmpty || _filterType != 'all'
                            ? 'لا توجد حركات تطابق البحث أو الفلتر.'
                            : extraProductId == null
                                ? 'لم تُسجَّل أي حركة مخزون في هذا الفرع بعد.'
                                : 'لم تُسجَّل أي حركة لهذا المنتج في هذا الفرع بعد.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Reads the `extra` value passed by the router, when present.
  static Map<String, String?>? _readExtra(BuildContext context) {
    final GoRouterState state = GoRouterState.of(context);
    final Object? extra = state.extra;
    if (extra is Map<String, String?>) {
      return extra;
    }
    if (extra is Map) {
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
// Search & Filters Bar
// -----------------------------------------------------------------------------

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.searchController,
    required this.searchQuery,
    required this.filterType,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onFilterChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final String filterType;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'ابحث باسم المنتج...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: onClearSearch,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              isDense: true,
            ),
            onChanged: onSearchChanged,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: <Widget>[
              _FilterChip(
                label: 'الكل',
                value: 'all',
                currentValue: filterType,
                onSelected: onFilterChanged,
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'إدخال (وارد)',
                value: 'in',
                currentValue: filterType,
                onSelected: onFilterChanged,
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'إخراج (صادر)',
                value: 'out',
                currentValue: filterType,
                onSelected: onFilterChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.currentValue,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String currentValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: currentValue == value,
      onSelected: (_) => onSelected(value),
      showCheckmark: false,
    );
  }
}

// -----------------------------------------------------------------------------
// Movement Card (Improved Design)
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

    // Green for incoming (increase), Red for outgoing (decrease)
    final Color accent = isIncrease ? const Color(0xFF0F7B6C) : scheme.error;

    final NumberFormat numberFormat = NumberFormat.decimalPattern('en_US');
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    final DateFormat dateTimeFormat = DateFormat('yyyy/MM/dd HH:mm', 'en_US');

    final String quantityLabel =
        '${isIncrease ? '+' : '-'}'
        '${numberFormat.format(movement.absoluteQuantity)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isIncrease ? Icons.arrow_downward : Icons.arrow_upward,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Product & Meta Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        productName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _movementTypeLabel(movement.movementType),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          Text(
                            dateTimeFormat.format(movement.createdAt.toLocal()),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Quantity & Cost
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      quantityLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (movement.hasUnitCost) ...[
                      const SizedBox(height: 2),
                      Text(
                        'تكلفة: ${moneyFormat.format(movement.unitCost!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (movement.hasNotes) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                movement.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
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
