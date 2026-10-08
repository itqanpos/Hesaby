// lib/features/purchases/presentation/pages/purchase_detail_page.dart

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
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../../suppliers/domain/entities/supplier.dart';
import '../../../suppliers/presentation/providers/supplier_providers.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_item.dart';
import '../../domain/entities/purchase_receipt.dart';
import '../../domain/entities/supplier_payment.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../dialogs/purchase_print_dialog.dart';
import '../dialogs/supplier_payment_dialog.dart';
import '../providers/purchase_providers.dart';
import '../providers/supplier_payment_providers.dart';

/// Read-only view of a single purchase order, with actions to edit,
/// confirm, cancel, record payments, and print the receipt.
class PurchaseDetailPage extends ConsumerStatefulWidget {
  const PurchaseDetailPage({super.key});

  @override
  ConsumerState<PurchaseDetailPage> createState() =>
      _PurchaseDetailPageState();
}

class _PurchaseDetailPageState extends ConsumerState<PurchaseDetailPage> {
  bool _isActing = false;

  @override
  Widget build(BuildContext context) {
    final GoRouterState state = GoRouterState.of(context);
    final String? id = state.pathParameters['id'];

    if (id == null || id.isEmpty) {
      return AppShell(
        appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
        body: const AppEmptyView(
          icon: Icons.receipt_long_outlined,
          title: 'فاتورة غير معروفة',
          message: 'لم يتم تحديد رقم الفاتورة.',
        ),
      );
    }

    final AsyncValue<List<Purchase>> purchasesAsync =
        ref.watch(purchasesProvider);
    final AsyncValue<List<PurchaseItem>> itemsAsync =
        ref.watch(purchaseItemsProvider(id));
    final AsyncValue<List<SupplierPayment>> paymentsAsync =
        ref.watch(supplierPaymentsForPurchaseProvider(id));
    final AsyncValue<List<Supplier>> suppliersAsync =
        ref.watch(suppliersProvider);
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    final bool anyLoading = purchasesAsync.isLoading ||
        itemsAsync.isLoading ||
        paymentsAsync.isLoading ||
        suppliersAsync.isLoading ||
        productsAsync.isLoading ||
        unitsAsync.isLoading;

    final Object? firstError = purchasesAsync.error ??
        itemsAsync.error ??
        paymentsAsync.error ??
        suppliersAsync.error ??
        productsAsync.error ??
        unitsAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('تفاصيل الفاتورة'),
        actions: <Widget>[
          IconButton(
            tooltip: 'طباعة',
            onPressed: anyLoading || _isActing
                ? null
                : () => _print(context),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: anyLoading || _isActing
                ? null
                : () {
                    ref.invalidate(purchasesProvider);
                    ref.invalidate(purchaseItemsProvider(id));
                    ref.invalidate(supplierPaymentsForPurchaseProvider(id));
                  },
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
              title: 'تعذّر تحميل الفاتورة',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(purchasesProvider);
                ref.invalidate(purchaseItemsProvider(id));
                ref.invalidate(supplierPaymentsForPurchaseProvider(id));
                ref.invalidate(suppliersProvider);
                ref.invalidate(productsProvider);
                ref.invalidate(unitsProvider);
              },
            );
          }

          final List<Purchase> purchases =
              purchasesAsync.value ?? const <Purchase>[];
          final List<PurchaseItem> items =
              itemsAsync.value ?? const <PurchaseItem>[];
          final List<SupplierPayment> payments =
              paymentsAsync.value ?? const <SupplierPayment>[];
          final List<Supplier> suppliers =
              suppliersAsync.value ?? const <Supplier>[];
          final List<Product> products =
              productsAsync.value ?? const <Product>[];
          final List<Unit> units = unitsAsync.value ?? const <Unit>[];

          final Purchase? purchase = _findPurchase(purchases, id);
          if (purchase == null) {
            return AppErrorView(
              title: 'الفاتورة غير موجودة',
              message:
                  'ربما تم حذفها أو لا تملك صلاحية الوصول إليها.',
              retryLabel: 'إعادة المحاولة',
              onRetry: () => ref.invalidate(purchasesProvider),
            );
          }

          final String supplierName =
              _resolveSupplierName(suppliers, purchase.supplierId);
          final Map<String, String> productNames = <String, String>{
            for (final Product product in products)
              product.id: product.name,
          };
          final Map<String, String> unitNames = <String, String>{
            for (final Unit unit in units) unit.id: unit.name,
          };

          final double totalPaid = payments.fold<double>(
            0,
            (double s, SupplierPayment p) => s + p.amount,
          );
          final double remaining =
              (purchase.total - totalPaid).clamp(0.0, double.infinity);

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _HeaderCard(
                  purchase: purchase,
                  supplierName: supplierName,
                ),
                const SizedBox(height: 16),
                _ItemsCard(
                  items: items,
                  productNames: productNames,
                  unitNames: unitNames,
                ),
                const SizedBox(height: 16),
                _TotalsCard(purchase: purchase),
                const SizedBox(height: 16),
                _PaymentsCard(
                  supplierName: supplierName,
                  payments: payments,
                  totalPaid: totalPaid,
                  remaining: remaining,
                  canPay: !purchase.isCancelled,
                  onAddPayment: () => _recordPayment(
                    context,
                    purchase: purchase,
                    supplierName: supplierName,
                    remaining: remaining,
                  ),
                ),
                const SizedBox(height: 24),
                _ActionsSection(
                  purchase: purchase,
                  isBusy: _isActing,
                  onEdit: () => _openEdit(context, purchase),
                  onConfirm: () => _confirm(context, purchase),
                  onCancel: () => _cancel(context, purchase),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _openEdit(BuildContext context, Purchase purchase) {
    context.pushNamed(
      AppRouter.purchaseEditName,
      pathParameters: <String, String>{'id': purchase.id},
    );
  }

  Future<void> _print(BuildContext context) async {
    // Re-read every dependency at the moment of printing so any mutation
    // performed since the page opened is reflected in the output.
    final GoRouterState state = GoRouterState.of(context);
    final String? id = state.pathParameters['id'];
    if (id == null || id.isEmpty) {
      return;
    }

    final Purchase? purchase = _findPurchase(
      ref.read(purchasesProvider).value ?? const <Purchase>[],
      id,
    );
    if (purchase == null) {
      return;
    }

    final Supplier? supplier = _findSupplier(
      ref.read(suppliersProvider).value ?? const <Supplier>[],
      purchase.supplierId,
    );

    final List<PurchaseItem> items =
        ref.read(purchaseItemsProvider(id)).value ??
            const <PurchaseItem>[];
    final List<Product> products =
        ref.read(productsProvider).value ?? const <Product>[];
    final List<Unit> units =
        ref.read(unitsProvider).value ?? const <Unit>[];

    final Map<String, String> productNames = <String, String>{
      for (final Product p in products) p.id: p.name,
    };
    final Map<String, String> unitNames = <String, String>{
      for (final Unit u in units) u.id: u.name,
    };

    final CompanyContextState contextState =
        ref.read(companyContextProvider);
    final String companyName =
        contextState.currentCompany?.name ?? '—';
    final String branchName =
        contextState.currentBranch?.name ?? '—';
    final String footer = ref.read(receiptFooterProvider);

    final PurchaseReceipt receipt = PurchaseReceipt(
      purchaseId: purchase.id,
      invoiceNumber: purchase.invoiceNumber,
      purchaseDate: purchase.purchaseDate,
      companyName: companyName,
      branchName: branchName,
      supplierName: supplier?.name ?? 'مورد محذوف',
      supplierPhone: supplier?.phone,
      supplierEmail: supplier?.email,
      supplierAddress: supplier?.address,
      lines: <PurchaseReceiptLine>[
        for (final PurchaseItem item in items)
          PurchaseReceiptLine(
            productName:
                productNames[item.productId] ?? 'منتج محذوف',
            unitName: unitNames[item.unitId] ?? 'وحدة',
            quantity: item.quantity,
            unitCost: item.unitCost,
            lineTotal: item.lineTotal,
          ),
      ],
      subtotal: purchase.subtotal,
      discount: purchase.discount,
      taxAmount: purchase.taxAmount,
      total: purchase.total,
      status: purchase.status,
      notes: purchase.notes,
      footer: footer,
    );

    if (!context.mounted) {
      return;
    }
    await showPurchasePrintDialog(context: context, receipt: receipt);
  }

  Future<void> _recordPayment(
    BuildContext context, {
    required Purchase purchase,
    required String supplierName,
    required double remaining,
  }) async {
    final bool? saved = await showSupplierPaymentDialog(
      context: context,
      supplierId: purchase.supplierId,
      supplierName: supplierName,
      purchaseId: purchase.id,
      purchaseLabel: purchase.invoiceNumber,
      suggestedAmount: remaining > 0 ? remaining : null,
    );
    if (saved == true && context.mounted) {
      ref.invalidate(supplierPaymentsForPurchaseProvider(purchase.id));
    }
  }

  Future<void> _confirm(BuildContext context, Purchase purchase) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('تأكيد الفاتورة'),
        content: const Text(
          'سيتم تأكيد الفاتورة وإضافة الكميات إلى المخزون. '
          'لا يمكن التعديل بعد التأكيد.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'رجوع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'تأكيد',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    setState(() => _isActing = true);
    try {
      await ref
          .read(purchasesProvider.notifier)
          .confirmPurchase(purchase.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد الفاتورة')),
      );
    } on PurchaseException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    } on Object {
      if (!context.mounted) {
        return;
      }
      _showError(
        context,
        const PurchaseException(type: PurchaseFailureType.unknown),
      );
    } finally {
      if (mounted) {
        setState(() => _isActing = false);
      }
    }
  }

  Future<void> _cancel(BuildContext context, Purchase purchase) async {
    final bool wasConfirmed = purchase.isConfirmed;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: Text(
          wasConfirmed
              ? 'سيتم إلغاء الفاتورة وعكس كميات المخزون. '
                  'قد يفشل الإلغاء إذا استُهلكت الكميات.'
              : 'سيتم إلغاء الفاتورة. لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'رجوع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'إلغاء الفاتورة',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    setState(() => _isActing = true);
    try {
      await ref
          .read(purchasesProvider.notifier)
          .cancelPurchase(purchase.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الفاتورة')),
      );
    } on PurchaseException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    } on Object {
      if (!context.mounted) {
        return;
      }
      _showError(
        context,
        const PurchaseException(type: PurchaseFailureType.unknown),
      );
    } finally {
      if (mounted) {
        setState(() => _isActing = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Lookup helpers
  // ---------------------------------------------------------------------------

  static Purchase? _findPurchase(List<Purchase> purchases, String id) {
    for (final Purchase purchase in purchases) {
      if (purchase.id == id) {
        return purchase;
      }
    }
    return null;
  }

  static Supplier? _findSupplier(
    List<Supplier> suppliers,
    String supplierId,
  ) {
    for (final Supplier supplier in suppliers) {
      if (supplier.id == supplierId) {
        return supplier;
      }
    }
    return null;
  }

  static String _resolveSupplierName(
    List<Supplier> suppliers,
    String supplierId,
  ) {
    for (final Supplier supplier in suppliers) {
      if (supplier.id == supplierId) {
        return supplier.name;
      }
    }
    return 'مورد محذوف';
  }
}

// -----------------------------------------------------------------------------
// Header card
// -----------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.purchase,
    required this.supplierName,
  });

  final Purchase purchase;
  final String supplierName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DateFormat dateFormat = DateFormat.yMd('ar_EG');
    final DateFormat dateTimeFormat = DateFormat.yMd('ar_EG').add_Hm();

    final (Color badgeBg, Color badgeFg) = _statusColors(
      scheme,
      purchase.status,
    );

    final String? invoice = purchase.invoiceNumber;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'بيانات الفاتورة',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      _statusLabel(purchase.status),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: badgeFg,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(
              theme,
              label: 'رقم الفاتورة',
              value: (invoice != null && invoice.isNotEmpty)
                  ? invoice
                  : '—',
            ),
            _row(theme, label: 'المورد', value: supplierName),
            _row(
              theme,
              label: 'تاريخ الفاتورة',
              value: dateFormat.format(purchase.purchaseDate.toLocal()),
            ),
            if (purchase.wasConfirmed && purchase.confirmedAt != null)
              _row(
                theme,
                label: 'تم التأكيد في',
                value: dateTimeFormat.format(
                  purchase.confirmedAt!.toLocal(),
                ),
              ),
            if (purchase.wasCancelled && purchase.cancelledAt != null)
              _row(
                theme,
                label: 'تم الإلغاء في',
                value: dateTimeFormat.format(
                  purchase.cancelledAt!.toLocal(),
                ),
              ),
            if (purchase.hasNotes)
              _row(
                theme,
                label: 'ملاحظات',
                value: purchase.notes!,
                multiline: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    ThemeData theme, {
    required String label,
    required String value,
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Items card
// -----------------------------------------------------------------------------

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({
    required this.items,
    required this.productNames,
    required this.unitNames,
  });

  final List<PurchaseItem> items;
  final Map<String, String> productNames;
  final Map<String, String> unitNames;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('بنود الفاتورة', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                'لا توجد بنود في هذه الفاتورة.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (int i = 0; i < items.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == items.length - 1 ? 0 : 8,
                  ),
                  child: _ItemRow(
                    item: items[i],
                    productName: productNames[items[i].productId] ??
                        'منتج محذوف',
                    unitName: unitNames[items[i].unitId] ?? 'وحدة',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.productName,
    required this.unitName,
  });

  final PurchaseItem item;
  final String productName;
  final String unitName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat numberFormat = NumberFormat.decimalPattern('ar_EG');
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              productName,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Text(
                  '${numberFormat.format(item.quantity)} $unitName',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                Text(
                  '× ${moneyFormat.format(item.unitCost)}',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  moneyFormat.format(item.lineTotal),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (item.hasNotes) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                item.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
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
// Totals card
// -----------------------------------------------------------------------------

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.purchase});

  final Purchase purchase;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('الإجماليات', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _line(
              theme,
              'المجموع الفرعي',
              moneyFormat.format(purchase.subtotal),
            ),
            const SizedBox(height: 4),
            _line(
              theme,
              'الخصم',
              moneyFormat.format(purchase.discount),
            ),
            const SizedBox(height: 4),
            _line(
              theme,
              'الضريبة',
              moneyFormat.format(purchase.taxAmount),
            ),
            const Divider(height: 20),
            _line(
              theme,
              'الإجمالي',
              moneyFormat.format(purchase.total),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(
    ThemeData theme,
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: emphasized
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                )
              : theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Payments card
// -----------------------------------------------------------------------------

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({
    required this.supplierName,
    required this.payments,
    required this.totalPaid,
    required this.remaining,
    required this.canPay,
    required this.onAddPayment,
  });

  final String supplierName;
  final List<SupplierPayment> payments;
  final double totalPaid;
  final double remaining;
  final bool canPay;
  final VoidCallback onAddPayment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    final bool isFullyPaid = remaining <= 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'الدفعات للمورد',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (canPay && !isFullyPaid)
                  AppButton(
                    label: 'تسجيل دفعة',
                    icon: Icons.add,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    onPressed: onAddPayment,
                  ),
              ],
            ),

            const SizedBox(height: 12),

            _summaryRow(
              theme,
              label: 'إجمالي الفاتورة',
              value: moneyFormat.format(totalPaid + remaining),
            ),
            const SizedBox(height: 4),
            _summaryRow(
              theme,
              label: 'المدفوع',
              value: moneyFormat.format(totalPaid),
              color: const Color(0xFF0F7B6C),
            ),
            const SizedBox(height: 4),
            _summaryRow(
              theme,
              label: 'المتبقي',
              value: moneyFormat.format(remaining),
              color: isFullyPaid
                  ? const Color(0xFF0F7B6C)
                  : const Color(0xFFC62828),
              emphasized: true,
            ),

            if (isFullyPaid) ...<Widget>[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F7B6C).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFF0F7B6C),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'الفاتورة مدفوعة بالكامل',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF0F7B6C),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const Divider(height: 24),

            if (payments.isEmpty)
              Text(
                'لا توجد دفعات مسجلة على هذه الفاتورة بعد.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              for (int i = 0; i < payments.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == payments.length - 1 ? 0 : 6,
                  ),
                  child: _PaymentRow(payment: payments[i]),
                ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    ThemeData theme, {
    required String label,
    required String value,
    Color? color,
    bool emphasized = false,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        Text(
          value,
          style: (emphasized
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium)
              ?.copyWith(
            color: color ?? theme.colorScheme.onSurface,
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final SupplierPayment payment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final DateFormat dateFormat = DateFormat.yMd('ar_EG');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF0F7B6C).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.payments_outlined,
                size: 16,
                color: Color(0xFF0F7B6C),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    payment.methodLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateFormat.format(payment.paymentDate.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (payment.hasReference) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      'مرجع: ${payment.reference}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Text(
              moneyFormat.format(payment.amount),
              style: theme.textTheme.titleSmall?.copyWith(
                color: const Color(0xFF0F7B6C),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Actions section
// -----------------------------------------------------------------------------

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({
    required this.purchase,
    required this.isBusy,
    required this.onEdit,
    required this.onConfirm,
    required this.onCancel,
  });

  final Purchase purchase;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final List<Widget> buttons = <Widget>[];

    if (purchase.canEdit) {
      buttons.add(
        Expanded(
          child: AppButton(
            label: 'تعديل',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: isBusy ? null : onEdit,
          ),
        ),
      );
    }

    if (purchase.isDraft) {
      if (buttons.isNotEmpty) {
        buttons.add(const SizedBox(width: 12));
      }
      buttons.add(
        Expanded(
          child: AppButton(
            label: 'تأكيد',
            icon: Icons.check_circle_outline,
            isLoading: isBusy,
            onPressed: isBusy ? null : onConfirm,
          ),
        ),
      );
    }

    if (purchase.canTransition) {
      if (buttons.isNotEmpty) {
        buttons.add(const SizedBox(width: 12));
      }
      buttons.add(
        Expanded(
          child: AppButton(
            label: 'إلغاء الفاتورة',
            icon: Icons.cancel_outlined,
            variant: AppButtonVariant.danger,
            onPressed: isBusy ? null : onCancel,
          ),
        ),
      );
    }

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(children: buttons);
  }
}

// -----------------------------------------------------------------------------
// Localization helpers
// -----------------------------------------------------------------------------

String _statusLabel(String status) {
  switch (status) {
    case PurchaseStatus.draft:
      return 'مسودة';
    case PurchaseStatus.confirmed:
      return 'مؤكدة';
    case PurchaseStatus.cancelled:
      return 'ملغاة';
    default:
      return 'غير معروفة';
  }
}

(Color background, Color foreground) _statusColors(
  ColorScheme scheme,
  String status,
) {
  switch (status) {
    case PurchaseStatus.draft:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    case PurchaseStatus.confirmed:
      return (scheme.primaryContainer, scheme.onPrimaryContainer);
    case PurchaseStatus.cancelled:
      return (scheme.errorContainer, scheme.onErrorContainer);
    default:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
  }
}

void _showError(BuildContext context, PurchaseException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _errorMessage(Object error) {
  if (error is PurchaseException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(PurchaseFailureType type) => switch (type) {
      PurchaseFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      PurchaseFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      PurchaseFailureType.notFound =>
        'الفاتورة المطلوبة غير موجودة أو تم حذفها.',
      PurchaseFailureType.invalidStatusTransition =>
        'لا يمكن إجراء هذه العملية على الفاتورة في حالتها الحالية.',
      PurchaseFailureType.emptyPurchase =>
        'لا يمكن تأكيد فاتورة بدون بنود.',
      PurchaseFailureType.invoiceNumberConflict =>
        'يوجد فاتورة أخرى بنفس الرقم في هذه الشركة.',
      PurchaseFailureType.supplierNotFound =>
        'المورد المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.productNotFound =>
        'أحد المنتجات المختارة غير متاح.',
      PurchaseFailureType.unitNotFound =>
        'إحدى الوحدات المختارة غير متاحة.',
      PurchaseFailureType.insufficientStock =>
        'لا يمكن عكس الفاتورة؛ بعض الكميات استُهلكت بالفعل.',
      PurchaseFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الفاتورة. يرجى المحاولة لاحقًا.',
      PurchaseFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };
