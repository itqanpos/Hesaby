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
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/product_unit.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../domain/entities/inventory_balance.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../providers/inventory_providers.dart';

/// Inventory page: current stock levels for the selected branch.
///
/// Interaction model:
/// * Tapping a card opens the movement history for that product.
/// * Manual adjustments are reached only from the per-card overflow menu.
///
/// Unit handling:
/// `inventory_balances.quantity_on_hand` is always expressed in the
/// product's **base** unit. When the operator records a manual movement
/// in a non-base unit (e.g. "بلته"), the dialog multiplies the entered
/// quantity by the unit's conversion factor before persisting it. The
/// original `unit_id` is stored on the row for reporting only.
class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CompanyContextState contextState =
        ref.watch(companyContextProvider);
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

    final bool anyLoading =
        balancesAsync.isLoading || productsAsync.isLoading;
    final Object? firstError = balancesAsync.error ?? productsAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('المخزون'),
        actions: <Widget>[
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
              _filter(balances, productsById, _searchQuery);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ---- Summary KPI row ----
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: _SummaryRow(balances: balances),
              ),

              // ---- Search ----
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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

              // ---- List ----
              Expanded(
                child: balances.isEmpty
                    ? const AppEmptyView(
                        icon: Icons.inventory_2_outlined,
                        title: 'لا يوجد مخزون',
                        message:
                            'لم تُسجَّل أي حركات مخزون في هذا الفرع بعد.',
                      )
                    : filtered.isEmpty
                        ? const AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message: 'لم يُطابق أي منتج كلمة البحث.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder:
                                (BuildContext context, int index) {
                              final InventoryBalance balance =
                                  filtered[index];
                              final Product? product =
                                  productsById[balance.productId];

                              return _BalanceCard(
                                balance: balance,
                                productName:
                                    product?.name ?? 'منتج محذوف',
                                sku: product?.sku,
                                onOpenMovements: () => _openMovements(
                                  context,
                                  branchId: branchId,
                                  productId: balance.productId,
                                ),
                                onAdjust: () => _openAdjustment(
                                  context,
                                  branchId: branchId,
                                  productId: balance.productId,
                                  productName:
                                      product?.name ?? 'منتج محذوف',
                                  currentQuantity:
                                      balance.quantityOnHand,
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

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  List<InventoryBalance> _filter(
    List<InventoryBalance> balances,
    Map<String, Product> productsById,
    String query,
  ) {
    final String trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return balances;
    }
    return balances.where((InventoryBalance balance) {
      final Product? product = productsById[balance.productId];
      final String name = (product?.name ?? '').toLowerCase();
      final String sku = (product?.sku ?? '').toLowerCase();
      final String barcode = (product?.barcode ?? '').toLowerCase();
      return name.contains(trimmed) ||
          sku.contains(trimmed) ||
          barcode.contains(trimmed);
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

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

    if (!context.mounted || saved != true) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('تم تسجيل الحركة')),
      );
  }

  void _openMovements(
    BuildContext context, {
    required String branchId,
    String? productId,
  }) {
    context.pushNamed(
      AppRouter.stockMovementsName,
      extra: <String, String?>{
        'branchId': branchId,
        'productId': productId,
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Summary row
// -----------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.balances});

  final List<InventoryBalance> balances;

  @override
  Widget build(BuildContext context) {
    int itemCount = 0;
    int outOfStock = 0;
    double totalValue = 0;

    for (final InventoryBalance b in balances) {
      itemCount++;
      if (b.quantityOnHand <= 0) {
        outOfStock++;
      }
      totalValue += b.totalValue;
    }

    return Row(
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
            label: 'قيمة المخزون',
            value: AppFormatters.money(totalValue),
            color: const Color(0xFF0F7B6C),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            icon: Icons.warning_amber_outlined,
            label: 'نفد',
            value: AppFormatters.integer(outOfStock),
            color: outOfStock > 0
                ? const Color(0xFFC62828)
                : const Color(0xFF7B5E3A),
            emphasize: outOfStock > 0,
          ),
        ),
      ],
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
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: emphasize ? color : scheme.onSurface,
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

// -----------------------------------------------------------------------------
// Balance card
// -----------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.productName,
    required this.sku,
    required this.onOpenMovements,
    required this.onAdjust,
  });

  final InventoryBalance balance;
  final String productName;
  final String? sku;
  final VoidCallback onOpenMovements;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final bool inStock = !balance.isOutOfStock;
    final String? skuValue = sku;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Tapping the card opens the movement history — the natural
        // "details" view. Adjustments are reachable only from the
        // overflow menu so an accidental tap never opens the dialog.
        onTap: onOpenMovements,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: inStock
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                foregroundColor: inStock
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                child: const Icon(Icons.inventory_2_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      productName,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (skuValue != null && skuValue.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        'SKU: $skuValue',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Text(
                          AppFormatters.quantity(balance.quantityOnHand),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: inStock
                                ? scheme.primary
                                : scheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'متوسط: '
                            '${AppFormatters.money(balance.averageCost)}',
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'القيمة: '
                      '${AppFormatters.money(balance.totalValue)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_BalanceAction>(
                tooltip: 'خيارات',
                onSelected: (_BalanceAction action) {
                  switch (action) {
                    case _BalanceAction.movements:
                      onOpenMovements();
                    case _BalanceAction.adjust:
                      onAdjust();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_BalanceAction>>[
                  const PopupMenuItem<_BalanceAction>(
                    value: _BalanceAction.movements,
                    child: ListTile(
                      leading: Icon(Icons.history),
                      title: Text('سجل الحركات'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<_BalanceAction>(
                    value: _BalanceAction.adjust,
                    child: ListTile(
                      leading: Icon(Icons.tune_outlined),
                      title: Text('تسجيل حركة'),
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

enum _BalanceAction { movements, adjust }

// -----------------------------------------------------------------------------
// Unit option — internal value object for the adjustment dialog
// -----------------------------------------------------------------------------

@immutable
class _UnitOption {
  const _UnitOption({
    required this.id,
    required this.name,
    required this.conversionFactor,
    required this.isBase,
  });

  final String id;
  final String name;
  final double conversionFactor;
  final bool isBase;
}

// -----------------------------------------------------------------------------
// Adjustment dialog
// -----------------------------------------------------------------------------

class _StockAdjustmentDialog extends ConsumerStatefulWidget {
  const _StockAdjustmentDialog({
    required this.branchId,
    required this.productId,
    required this.productName,
    required this.currentQuantity,
  });

  final String branchId;
  final String productId;
  final String productName;

  /// Current balance in **base units**.
  final double currentQuantity;

  @override
  ConsumerState<_StockAdjustmentDialog> createState() =>
      _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState
    extends ConsumerState<_StockAdjustmentDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _unitCostController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  /// One of:
  /// * [StockMovementType.openingBalance] — first-ever movement, only
  ///   offered when the current balance is zero.
  /// * [StockMovementType.adjustmentIn]   — add stock.
  /// * [StockMovementType.adjustmentOut]  — remove stock.
  String _movementType = StockMovementType.adjustmentIn;

  /// Currently selected unit option. Resolved on first build when the
  /// base unit is available.
  String? _selectedUnitId;

  bool _isSubmitting = false;
  InventoryFailureType? _failureType;

  bool get _isIncoming =>
      _movementType == StockMovementType.adjustmentIn ||
      _movementType == StockMovementType.openingBalance;

  @override
  void dispose() {
    _quantityController.dispose();
    _unitCostController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Unit option resolution
  // ---------------------------------------------------------------------------

  List<_UnitOption> _buildUnitOptions(
    List<ProductUnit> productUnits,
    List<Unit> units,
    String baseUnitId,
  ) {
    String nameOf(String unitId) {
      for (final Unit u in units) {
        if (u.id == unitId) return u.name;
      }
      return 'وحدة';
    }

    final List<_UnitOption> options = <_UnitOption>[
      _UnitOption(
        id: baseUnitId,
        name: nameOf(baseUnitId),
        conversionFactor: 1,
        isBase: true,
      ),
    ];

    for (final ProductUnit pu in productUnits) {
      options.add(
        _UnitOption(
          id: pu.unitId,
          name: nameOf(pu.unitId),
          conversionFactor: pu.conversionFactor,
          isBase: false,
        ),
      );
    }

    return options;
  }

  _UnitOption? _resolveSelectedOption(List<_UnitOption> options) {
    if (options.isEmpty) return null;

    final String? id = _selectedUnitId;
    if (id != null) {
      for (final _UnitOption o in options) {
        if (o.id == id) return o;
      }
    }
    // Fall back to the base unit (first element).
    return options.first;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit(List<_UnitOption> options) async {
    FocusScope.of(context).unfocus();

    if (_failureType != null) {
      setState(() => _failureType = null);
    }

    final bool isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final _UnitOption? unit = _resolveSelectedOption(options);
    if (unit == null) {
      setState(() => _failureType = InventoryFailureType.invalidMovement);
      return;
    }

    final double? enteredQuantity =
        double.tryParse(_quantityController.text.trim());
    if (enteredQuantity == null || enteredQuantity <= 0) {
      setState(() => _failureType = InventoryFailureType.invalidMovement);
      return;
    }

    // Convert to base units before persisting.
    final double baseQuantity = enteredQuantity * unit.conversionFactor;
    final double signedBaseQuantity =
        _isIncoming ? baseQuantity : -baseQuantity;

    // Unit cost: user enters cost per the *selected* unit; we store the
    // per-base-unit cost.
    final String costText = _unitCostController.text.trim();
    final double? enteredUnitCost = costText.isEmpty
        ? null
        : double.tryParse(costText);
    final double? baseUnitCost = enteredUnitCost == null
        ? null
        : enteredUnitCost / unit.conversionFactor;

    final String notesText = _notesController.text.trim();
    final String? notes = notesText.isEmpty ? null : notesText;

    setState(() => _isSubmitting = true);

    final InventoryBalancesNotifier notifier =
        ref.read(inventoryBalancesProvider(widget.branchId).notifier);

    try {
      await notifier.recordMovement(
        productId: widget.productId,
        movementType: _movementType,
        quantity: signedBaseQuantity,
        unitId: unit.id,
        unitCost: _isIncoming ? baseUnitCost : null,
        notes: notes,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on InventoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failureType = error.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failureType = InventoryFailureType.unknown;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final InventoryFailureType? failure = _failureType;

    final AsyncValue<List<ProductUnit>> productUnitsAsync =
        ref.watch(productUnitsProvider(widget.productId));
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);

    // Resolve base unit id from the products list.
    String? baseUnitId;
    productsAsync.whenData((List<Product> products) {
      for (final Product p in products) {
        if (p.id == widget.productId) {
          baseUnitId = p.defaultUnitId;
          break;
        }
      }
    });

    final bool ready = productUnitsAsync.hasValue &&
        unitsAsync.hasValue &&
        baseUnitId != null;

    if (!ready) {
      return AlertDialog(
        title: Text('حركة مخزون — ${widget.productName}'),
        content: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final List<_UnitOption> options = _buildUnitOptions(
      productUnitsAsync.value ?? const <ProductUnit>[],
      unitsAsync.value ?? const <Unit>[],
      baseUnitId!,
    );
    final _UnitOption? selected = _resolveSelectedOption(options);
    final bool showOpening =
        widget.currentQuantity <= 0 && _movementType != StockMovementType.adjustmentOut;

    // Live preview: entered × conversion.
    final double? entered = double.tryParse(_quantityController.text.trim());
    final double? basePreview =
        (entered == null || selected == null) ? null : entered * selected.conversionFactor;

    return AlertDialog(
      title: Text('حركة مخزون — ${widget.productName}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ---- Current balance ----
                Text(
                  'الرصيد الحالي: '
                  '${AppFormatters.quantity(widget.currentQuantity)} '
                  '${options.first.name}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),

                // ---- Movement type ----
                SegmentedButton<String>(
                  segments: <ButtonSegment<String>>[
                    if (showOpening)
                      const ButtonSegment<String>(
                        value: StockMovementType.openingBalance,
                        label: Text('افتتاحي'),
                        icon: Icon(Icons.flag_outlined),
                      ),
                    const ButtonSegment<String>(
                      value: StockMovementType.adjustmentIn,
                      label: Text('إدخال'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                    const ButtonSegment<String>(
                      value: StockMovementType.adjustmentOut,
                      label: Text('إخراج'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                  ],
                  selected: <String>{_movementType},
                  onSelectionChanged: _isSubmitting
                      ? null
                      : (Set<String> selection) {
                          if (selection.isEmpty) return;
                          setState(() {
                            _movementType = selection.first;
                          });
                        },
                ),
                const SizedBox(height: 12),

                // ---- Unit selector ----
                if (options.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: selected?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الوحدة',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final _UnitOption option in options)
                        DropdownMenuItem<String>(
                          value: option.id,
                          child: Text(
                            option.isBase
                                ? '${option.name} (أساسية)'
                                : '${option.name} '
                                    '(= ${AppFormatters.quantity(option.conversionFactor)} '
                                    '${options.first.name})',
                          ),
                        ),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (String? value) {
                            setState(() => _selectedUnitId = value);
                          },
                  ),
                if (options.length > 1) const SizedBox(height: 12),

                // ---- Quantity ----
                AppTextField(
                  controller: _quantityController,
                  label: 'الكمية (${selected?.name ?? "وحدة"})',
                  hint: 'مثال: 5',
                  enabled: !_isSubmitting,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (String? value) {
                    final String trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return 'الرجاء إدخال الكمية';
                    final double? parsed = double.tryParse(trimmed);
                    if (parsed == null) return 'الرجاء إدخال رقم صحيح';
                    if (parsed <= 0) return 'يجب أن تكون الكمية أكبر من صفر';

                    // Early validation for outgoing movements.
                    if (_movementType ==
                            StockMovementType.adjustmentOut &&
                        selected != null) {
                      final double base =
                          parsed * selected.conversionFactor;
                      if (base > widget.currentQuantity) {
                        final double maxInUnit = widget.currentQuantity /
                            selected.conversionFactor;
                        return 'الكمية تتجاوز الرصيد. الأقصى: '
                            '${AppFormatters.quantity(maxInUnit)} '
                            '${selected.name}';
                      }
                    }
                    return null;
                  },
                ),

                // ---- Conversion preview ----
                if (basePreview != null &&
                    selected != null &&
                    !selected.isBase) ...<Widget>[
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: scheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'سيُسجَّل: '
                              '${AppFormatters.quantity(basePreview)} '
                              '${options.first.name} '
                              '(${AppFormatters.quantity(entered ?? 0)} × '
                              '${AppFormatters.quantity(selected.conversionFactor)})',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // ---- Unit cost (incoming only) ----
                if (_isIncoming) ...<Widget>[
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _unitCostController,
                    label: 'تكلفة الوحدة — اختياري '
                        '(${selected?.name ?? "وحدة"})',
                    hint: 'اتركه فارغًا للاحتفاظ بالمتوسط الحالي',
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (String? value) {
                      final String trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return null;
                      final double? parsed = double.tryParse(trimmed);
                      if (parsed == null) return 'الرجاء إدخال رقم صحيح';
                      if (parsed < 0) return 'لا يمكن أن تكون التكلفة سالبة';
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 12),

                // ---- Notes ----
                AppTextField(
                  controller: _notesController,
                  label: 'ملاحظات — اختياري',
                  enabled: !_isSubmitting,
                  maxLines: 3,
                  validator: (String? value) {
                    final String trimmed = value?.trim() ?? '';
                    if (trimmed.length > 1000) {
                      return 'الملاحظات طويلة جدًا (الحد الأقصى 1000 حرف)';
                    }
                    return null;
                  },
                ),

                if (failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _FailureBanner(message: _failureMessage(failure)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'إلغاء',
          variant: AppButtonVariant.text,
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'تسجيل',
          isLoading: _isSubmitting,
          onPressed: _isSubmitting ? null : () => _submit(options),
        ),
      ],
      backgroundColor: scheme.surface,
      scrollable: false,
    );
  }
}

// -----------------------------------------------------------------------------
// Inline error banner
// -----------------------------------------------------------------------------

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: scheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Localization helpers
// -----------------------------------------------------------------------------

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
        'الرصيد المطلوب غير موجود أو تم حذفه.',
      InventoryFailureType.insufficientStock =>
        'الرصيد غير كافٍ. لا يمكن إخراج كمية أكبر من المتوفرة.',
      InventoryFailureType.productNotFound =>
        'المنتج المختار غير متاح. يرجى إعادة اختياره.',
      InventoryFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      InventoryFailureType.invalidMovementType =>
        'نوع الحركة غير معروف.',
      InventoryFailureType.invalidMovement =>
        'بيانات الحركة غير صحيحة. يرجى التحقق من القيم.',
      InventoryFailureType.invalidResponse =>
        'تعذّر قراءة بيانات المخزون. يرجى المحاولة لاحقًا.',
      InventoryFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };
