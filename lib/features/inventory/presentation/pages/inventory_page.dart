// lib/features/inventory/presentation/pages/inventory_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../domain/entities/inventory_balance.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../providers/inventory_providers.dart';

/// Inventory page: current stock levels for the selected branch.
///
/// Data flow:
/// * Balances come from [inventoryBalancesProvider] (derived from the ledger
///   by the database trigger).
/// * Product names and SKUs are resolved from [productsProvider] so the UI
///   does not need a second round-trip per row.
/// * Recording a movement goes through [InventoryBalancesNotifier], which
///   appends to the ledger and lets the database update the balance.
///
/// The page contains no business rules: everything is delegated to the
/// repository and the database.
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
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: AppTextField(
                  controller: _searchController,
                  hint: 'ابحث بالاسم أو SKU',
                  prefixIcon: Icons.search,
                  onChanged: (String value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
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
                                onAdjust: () => _openAdjustment(
                                  context,
                                  branchId: branchId,
                                  productId: balance.productId,
                                  productName:
                                      product?.name ?? 'منتج محذوف',
                                  currentQuantity:
                                      balance.quantityOnHand,
                                ),
                                onViewMovements: () => _openMovements(
                                  context,
                                  branchId: branchId,
                                  productId: balance.productId,
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
      return name.contains(trimmed) || sku.contains(trimmed);
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تسجيل الحركة')),
    );
  }

  void _openMovements(
    BuildContext context, {
    required String branchId,
    String? productId,
  }) {
    // Navigation is performed by name only; the target page is imported by
    // the router, not here, avoiding a forward import.
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
// Balance card
// -----------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.productName,
    required this.sku,
    required this.onAdjust,
    required this.onViewMovements,
  });

  final InventoryBalance balance;
  final String productName;
  final String? sku;
  final VoidCallback onAdjust;
  final VoidCallback onViewMovements;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat numberFormat = NumberFormat.decimalPattern('ar_EG');
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    final bool inStock = !balance.isOutOfStock;
    final String? skuValue = sku;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onAdjust,
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
                          '${numberFormat.format(balance.quantityOnHand)} وحدة',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: inStock
                                ? scheme.primary
                                : scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'متوسط: ${moneyFormat.format(balance.averageCost)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'القيمة: ${moneyFormat.format(balance.totalValue)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_BalanceAction>(
                tooltip: 'خيارات',
                onSelected: (_BalanceAction action) {
                  switch (action) {
                    case _BalanceAction.adjust:
                      onAdjust();
                    case _BalanceAction.movements:
                      onViewMovements();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_BalanceAction>>[
                  const PopupMenuItem<_BalanceAction>(
                    value: _BalanceAction.adjust,
                    child: ListTile(
                      leading: Icon(Icons.tune_outlined),
                      title: Text('تسجيل حركة'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<_BalanceAction>(
                    value: _BalanceAction.movements,
                    child: ListTile(
                      leading: Icon(Icons.history),
                      title: Text('سجل الحركات'),
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

enum _BalanceAction { adjust, movements }

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

  /// `adjustment_in` or `adjustment_out`.
  String _movementType = StockMovementType.adjustmentIn;

  bool _isSubmitting = false;
  InventoryFailureType? _failureType;

  bool get _isIncoming => _movementType == StockMovementType.adjustmentIn;

  @override
  void dispose() {
    _quantityController.dispose();
    _unitCostController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_failureType != null) {
      setState(() => _failureType = null);
    }

    final bool isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final double? parsed =
        double.tryParse(_quantityController.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() {
        _failureType = InventoryFailureType.invalidMovement;
      });
      return;
    }

    final String costText = _unitCostController.text.trim();
    final double? unitCost = costText.isEmpty
        ? null
        : double.tryParse(costText);

    final String notesText = _notesController.text.trim();
    final String? notes = notesText.isEmpty ? null : notesText;

    final double signedQuantity = _isIncoming ? parsed : -parsed;

    setState(() => _isSubmitting = true);

    final InventoryBalancesNotifier notifier =
        ref.read(inventoryBalancesProvider(widget.branchId).notifier);

    try {
      await notifier.recordMovement(
        productId: widget.productId,
        movementType: _movementType,
        quantity: signedQuantity,
        unitCost: unitCost,
        notes: notes,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on InventoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _failureType = error.type;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _failureType = InventoryFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final InventoryFailureType? failure = _failureType;
    final NumberFormat numberFormat = NumberFormat.decimalPattern('ar_EG');

    return AlertDialog(
      title: Text('حركة مخزون — ${widget.productName}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'الرصيد الحالي: '
                  '${numberFormat.format(widget.currentQuantity)} وحدة',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: StockMovementType.adjustmentIn,
                      label: Text('إدخال'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                    ButtonSegment<String>(
                      value: StockMovementType.adjustmentOut,
                      label: Text('إخراج'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                  ],
                  selected: <String>{_movementType},
                  onSelectionChanged: _isSubmitting
                      ? null
                      : (Set<String> selection) {
                          if (selection.isEmpty) {
                            return;
                          }
                          setState(() {
                            _movementType = selection.first;
                          });
                        },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _quantityController,
                  label: 'الكمية',
                  hint: 'مثال: 10',
                  enabled: !_isSubmitting,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (String? value) {
                    final String trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'الرجاء إدخال الكمية';
                    }
                    final double? parsed = double.tryParse(trimmed);
                    if (parsed == null) {
                      return 'الرجاء إدخال رقم صحيح';
                    }
                    if (parsed <= 0) {
                      return 'يجب أن تكون الكمية أكبر من صفر';
                    }
                    return null;
                  },
                ),
                if (_isIncoming) ...<Widget>[
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _unitCostController,
                    label: 'تكلفة الوحدة — اختياري',
                    hint: 'اتركه فارغًا للاحتفاظ بالمتوسط الحالي',
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (String? value) {
                      final String trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return null;
                      }
                      final double? parsed = double.tryParse(trimmed);
                      if (parsed == null) {
                        return 'الرجاء إدخال رقم صحيح';
                      }
                      if (parsed < 0) {
                        return 'لا يمكن أن تكون التكلفة سالبة';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
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
          onPressed: _isSubmitting ? null : _submit,
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
