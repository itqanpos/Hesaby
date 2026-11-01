// lib/features/inventory/presentation/pages/inventory_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/domain/entities/company_member.dart';
import '../../../companies/domain/entities/member_permission.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../companies/presentation/providers/members_providers.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../domain/entities/inventory_balance.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../providers/inventory_providers.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterType = 'all'; // 'all', 'low', 'out'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CompanyContextState contextState = ref.watch(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;

    if (branchId == null) {
      return AppShell(
        appBar: AppBar(title: const Text('المخزون')),
        body: const AppEmptyView(
          icon: Icons.store_mall_directory_outlined,
          title: 'لم يتم اختيار فرع',
          message: 'اختر فرعًا من الصفحة الرئيسية لعرض مخزونه.',
        ),
      );
    }

    final AsyncValue<List<InventoryBalance>> balancesAsync =
        ref.watch(inventoryBalancesProvider(branchId));
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);
    final AsyncValue<CompanyMember?> memberAsync =
        ref.watch(currentMemberProvider);

    final CompanyMember? member = memberAsync.valueOrNull;
    final bool canAdjust = memberAsync.isLoading && !memberAsync.hasValue
        ? true
        : (member == null
            ? false
            : member.hasPermission(MemberPermission.inventoryAdjust));

    final bool anyLoading =
        balancesAsync.isLoading || productsAsync.isLoading;
    final Object? firstError = balancesAsync.error ?? productsAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('المخزون'),
        actions: <Widget>[
          IconButton(
            tooltip: 'جلسات الجرد',
            onPressed: () => _openStockCount(context),
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: 'سجل الحركات',
            onPressed: anyLoading || firstError != null
                ? null
                : () => _openMovements(context, branchId: branchId),
            icon: const Icon(Icons.history),
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
              title: 'تعذّر تحميل المخزون',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(inventoryBalancesProvider(branchId));
                ref.invalidate(productsProvider);
              },
            );
          }

          final List<InventoryBalance> balances =
              balancesAsync.value ?? const <InventoryBalance>[];
          final List<Product> products =
              productsAsync.value ?? const <Product>[];

          final Map<String, Product> productsById = <String, Product>{
            for (final Product product in products) product.id: product,
          };

          final List<InventoryBalance> filtered =
              _filter(balances, productsById, _searchQuery, _filterType);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- Dashboard KPIs ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _SummaryRow(balances: balances),
              ),

              // ---- Search ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppTextField(
                  controller: _searchController,
                  hint: 'ابحث بالاسم أو SKU أو الباركود',
                  prefixIcon: Icons.search,
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
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
              ),

              // ---- Filters ----
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'الكل',
                      value: 'all',
                      currentValue: _filterType,
                      onSelected: (v) => setState(() => _filterType = v),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'نواقص (≤ 10)',
                      value: 'low',
                      currentValue: _filterType,
                      onSelected: (v) => setState(() => _filterType = v),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'نفد المخزون',
                      value: 'out',
                      currentValue: _filterType,
                      onSelected: (v) => setState(() => _filterType = v),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),

              // ---- List ----
              Expanded(
                child: balances.isEmpty
                    ? const AppEmptyView(
                        icon: Icons.inventory_2_outlined,
                        title: 'لا يوجد مخزون',
                        message: 'لم تُسجَّل أي حركات مخزون في هذا الفرع بعد.',
                      )
                    : filtered.isEmpty
                        ? const AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message: 'لم يُطابق أي منتج معايير البحث أو الفلترة.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (BuildContext context, int index) {
                              final InventoryBalance balance = filtered[index];
                              final Product? product = productsById[balance.productId];

                              return _BalanceCard(
                                balance: balance,
                                productName: product?.name ?? 'منتج محذوف',
                                sku: product?.sku,
                                canAdjust: canAdjust,
                                onOpenMovements: () => _openMovements(
                                  context,
                                  branchId: branchId,
                                  productId: balance.productId,
                                ),
                                onAdjust: () => _openAdjustment(
                                  context,
                                  branchId: branchId,
                                  productId: balance.productId,
                                  productName: product?.name ?? 'منتج محذوف',
                                  currentQuantity: balance.quantityOnHand,
                                ),
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

  List<InventoryBalance> _filter(
    List<InventoryBalance> balances,
    Map<String, Product> productsById,
    String query,
    String filterType,
  ) {
    return balances.where((balance) {
      // 1. Text Search
      final String trimmed = query.trim().toLowerCase();
      if (trimmed.isNotEmpty) {
        final Product? product = productsById[balance.productId];
        final String name = (product?.name ?? '').toLowerCase();
        final String sku = (product?.sku ?? '').toLowerCase();
        final String barcode = (product?.barcode ?? '').toLowerCase();
        if (!name.contains(trimmed) &&
            !sku.contains(trimmed) &&
            !barcode.contains(trimmed)) {
          return false;
        }
      }

      // 2. Status Filter
      if (filterType == 'out') return balance.quantityOnHand <= 0;
      if (filterType == 'low') {
        return balance.quantityOnHand > 0 && balance.quantityOnHand <= 10;
      }
      return true;
    }).toList(growable: false);
  }

  Future<void> _openAdjustment(
    BuildContext context, {
    required String branchId,
    required String productId,
    required String productName,
    required double currentQuantity,
  }) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _StockAdjustmentDialog(
        branchId: branchId,
        productId: productId,
        productName: productName,
        currentQuantity: currentQuantity,
      ),
    );

    if (!context.mounted || saved != true) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('تم تسجيل الحركة')));
  }

  void _openMovements(BuildContext context, {required String branchId, String? productId}) {
    context.pushNamed(
      AppRouter.stockMovementsName,
      extra: <String, String?>{'branchId': branchId, 'productId': productId},
    );
  }

  void _openStockCount(BuildContext context) {
    context.pushNamed(AppRouter.stockCountSessionsName);
  }
}

// -----------------------------------------------------------------------------
// Filters
// -----------------------------------------------------------------------------

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
// Summary Dashboard
// -----------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.balances});

  final List<InventoryBalance> balances;

  @override
  Widget build(BuildContext context) {
    int itemCount = 0;
    int outOfStock = 0;
    int lowStock = 0;
    double totalValue = 0;

    for (final InventoryBalance b in balances) {
      itemCount++;
      if (b.quantityOnHand <= 0) {
        outOfStock++;
      } else if (b.quantityOnHand <= 10) {
        lowStock++;
      }
      totalValue += b.totalValue;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SummaryCard(
              icon: Icons.inventory_2_outlined,
              label: 'منتجات',
              value: AppFormatters.integer(itemCount),
              color: const Color(0xFF0288D1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryCard(
              icon: Icons.attach_money_outlined,
              label: 'القيمة',
              value: AppFormatters.money(totalValue),
              color: const Color(0xFF0F7B6C),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryCard(
              icon: Icons.warning_amber_outlined,
              label: 'نواقص',
              value: AppFormatters.integer(lowStock),
              color: lowStock > 0 ? Colors.orange : const Color(0xFF7B5E3A),
              emphasize: lowStock > 0,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryCard(
              icon: Icons.cancel_outlined,
              label: 'نفد',
              value: AppFormatters.integer(outOfStock),
              color: outOfStock > 0 ? const Color(0xFFC62828) : const Color(0xFF7B5E3A),
              emphasize: outOfStock > 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
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
        color: emphasize ? color.withValues(alpha: 0.08) : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize ? color.withValues(alpha: 0.5) : scheme.outlineVariant,
          width: emphasize ? 1.2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: emphasize ? color : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: emphasize ? color : scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Enterprise Balance Card
// -----------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.productName,
    required this.sku,
    required this.canAdjust,
    required this.onOpenMovements,
    required this.onAdjust,
  });

  final InventoryBalance balance;
  final String productName;
  final String? sku;
  final bool canAdjust;
  final VoidCallback onOpenMovements;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final bool isOutOfStock = balance.quantityOnHand <= 0;
    final bool isLowStock = balance.quantityOnHand > 0 && balance.quantityOnHand <= 10;

    final Color statusColor = isOutOfStock
        ? scheme.error
        : (isLowStock ? Colors.orange.shade800 : const Color(0xFF0F7B6C));

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenMovements,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isOutOfStock ? scheme.error.withValues(alpha: 0.3) : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ---- Header Row (Icon + Info + Quick Add) ----
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: statusColor.withValues(alpha: 0.12),
                      foregroundColor: statusColor,
                      child: const Icon(Icons.inventory_2_outlined, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            productName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (sku != null && sku!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'SKU: $sku',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (canAdjust)
                      IconButton.filledTonal(
                        tooltip: 'تسجيل حركة',
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: onAdjust,
                        style: IconButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // ---- Footer Row (Qty Badge + Pricing) ----
                Row(
                  children: <Widget>[
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(isOutOfStock ? Icons.warning_amber_rounded : Icons.check_circle_outline, size: 16, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            AppFormatters.quantity(balance.quantityOnHand),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Pricing
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'القيمة: ${AppFormatters.money(balance.totalValue)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'متوسط التكلفة: ${AppFormatters.money(balance.averageCost)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
