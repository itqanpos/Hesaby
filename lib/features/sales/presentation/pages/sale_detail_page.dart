// lib/features/sales/presentation/pages/sale_detail_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../pos/domain/entities/receipt.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/entities/sale_return.dart';
import '../../domain/repositories/sales_repository.dart';
import '../dialogs/sale_print_dialog.dart';
import '../dialogs/sale_return_dialog.dart';
import '../providers/sales_providers.dart';

/// Full-page view of a single sale invoice.
class SaleDetailPage extends ConsumerStatefulWidget {
  const SaleDetailPage({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends ConsumerState<SaleDetailPage> {
  bool _isActing = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Sale>> salesAsync = ref.watch(salesProvider);
    final AsyncValue<List<SaleItem>> itemsAsync =
        ref.watch(saleItemsProvider(widget.saleId));
    final AsyncValue<List<Customer>> customersAsync =
        ref.watch(customersProvider);
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    final bool anyLoading = salesAsync.isLoading ||
        itemsAsync.isLoading ||
        customersAsync.isLoading ||
        productsAsync.isLoading ||
        unitsAsync.isLoading;

    final Object? firstError = salesAsync.error ??
        itemsAsync.error ??
        customersAsync.error ??
        productsAsync.error ??
        unitsAsync.error;

    if (anyLoading) {
      return AppShell(
        appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
        body: const AppLoader(),
      );
    }

    if (firstError != null) {
      return AppShell(
        appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
        body: AppErrorView(
          title: 'تعذّر تحميل الفاتورة',
          message: _errorMessage(firstError),
          retryLabel: 'إعادة المحاولة',
          onRetry: () {
            ref.invalidate(salesProvider);
            ref.invalidate(saleItemsProvider(widget.saleId));
            ref.invalidate(customersProvider);
            ref.invalidate(productsProvider);
            ref.invalidate(unitsProvider);
          },
        ),
      );
    }

    final List<Sale> sales = salesAsync.value ?? const <Sale>[];
    final Sale? sale = _findSale(sales, widget.saleId);

    if (sale == null) {
      return AppShell(
        appBar: AppBar(title: const Text('تفاصيل الفاتورة')),
        body: AppErrorView(
          title: 'الفاتورة غير موجودة',
          message: 'ربما تم حذفها أو لا تملك صلاحية الوصول إليها.',
          retryLabel: 'رجوع',
          onRetry: () => context.pop(),
        ),
      );
    }

    final List<SaleItem> items = itemsAsync.value ?? const <SaleItem>[];
    final List<Customer> customers =
        customersAsync.value ?? const <Customer>[];
    final List<Product> products =
        productsAsync.value ?? const <Product>[];
    final List<Unit> units = unitsAsync.value ?? const <Unit>[];

    final String customerName =
        _resolveCustomerName(customers, sale.customerId);
    final Map<String, String> productNames = <String, String>{
      for (final Product product in products) product.id: product.name,
    };
    final Map<String, String> unitNames = <String, String>{
      for (final Unit unit in units) unit.id: unit.name,
    };

    return AppShell(
      appBar: AppBar(
        title: Text(
          (sale.invoiceNumber != null && sale.invoiceNumber!.isNotEmpty)
              ? sale.invoiceNumber!
              : 'تفاصيل الفاتورة',
        ),
        actions: <Widget>[
          if (sale.isConfirmed)
            IconButton(
              tooltip: 'إنشاء مرتجع',
              icon: const Icon(Icons.assignment_return_outlined),
              onPressed: _isActing || items.isEmpty
                  ? null
                  : () => _openReturnDialog(
                        sale,
                        items,
                        customers,
                        products,
                        units,
                      ),
            ),
          IconButton(
            tooltip: 'طباعة',
            icon: const Icon(Icons.print_outlined),
            onPressed: _isActing || items.isEmpty
                ? null
                : () => _printSale(
                      sale,
                      items,
                      customerName,
                      productNames,
                      unitNames,
                    ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _HeaderCard(sale: sale, customerName: customerName),
          const SizedBox(height: 12),
          _ActionsCard(
            sale: sale,
            isActing: _isActing,
            onEdit: () => _editSale(sale),
            onConfirm: () => _confirmSale(sale),
            onCancel: () => _cancelSale(sale),
          ),
          const SizedBox(height: 12),
          _ItemsCard(
            items: items,
            productNames: productNames,
            unitNames: unitNames,
          ),
          const SizedBox(height: 12),
          _TotalsCard(sale: sale),
          const SizedBox(height: 12),
          _ReturnsCard(sale: sale),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _editSale(Sale sale) {
    context.pushNamed(
      AppRouter.saleEditName,
      pathParameters: <String, String>{'id': sale.id},
    );
  }

  Future<void> _confirmSale(Sale sale) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('تأكيد الفاتورة'),
        content: const Text(
          'سيتم تأكيد الفاتورة وخصم الكميات من المخزون. '
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

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isActing = true);
    try {
      await ref.read(salesProvider.notifier).confirmSale(sale.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد الفاتورة')),
      );
    } on SaleException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(context, error);
    } on Object {
      if (!mounted) {
        return;
      }
      _showError(
        context,
        const SaleException(type: SalesFailureType.unknown),
      );
    } finally {
      if (mounted) {
        setState(() => _isActing = false);
      }
    }
  }

  Future<void> _cancelSale(Sale sale) async {
    final bool wasConfirmed = sale.isConfirmed;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: Text(
          wasConfirmed
              ? 'سيتم إلغاء الفاتورة وإرجاع الكميات إلى المخزون.'
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

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isActing = true);
    try {
      await ref.read(salesProvider.notifier).cancelSale(sale.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الفاتورة')),
      );
    } on SaleException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(context, error);
    } on Object {
      if (!mounted) {
        return;
      }
      _showError(
        context,
        const SaleException(type: SalesFailureType.unknown),
      );
    } finally {
      if (mounted) {
        setState(() => _isActing = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Return dialog
  // ---------------------------------------------------------------------------

  Future<void> _openReturnDialog(
    Sale sale,
    List<SaleItem> items,
    List<Customer> customers,
    List<Product> products,
    List<Unit> units,
  ) async {
    final bool? created = await showSaleReturnDialog(
      context: context,
      sale: sale,
      saleItems: items,
      customers: customers,
      products: products,
      units: units,
    );

    if (created != true || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('تم تسجيل المرتجع بنجاح.')),
      );
  }

  // ---------------------------------------------------------------------------
  // Print
  // ---------------------------------------------------------------------------

  Future<void> _printSale(
    Sale sale,
    List<SaleItem> items,
    String customerName,
    Map<String, String> productNames,
    Map<String, String> unitNames,
  ) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('لا يمكن طباعة فاتورة بدون بنود.'),
          ),
        );
      return;
    }

    final CompanyContextState contextState =
        ref.read(companyContextProvider);

    final Receipt receipt = Receipt(
      saleId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      dateTime: sale.saleDate,
      companyName: contextState.currentCompany?.name ?? '—',
      branchName: contextState.currentBranch?.name ?? '—',
      lines: <ReceiptLine>[
        for (final SaleItem item in items)
          ReceiptLine(
            productName: productNames[item.productId] ?? 'منتج محذوف',
            unitName: unitNames[item.unitId] ?? 'وحدة',
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            lineTotal: item.lineTotal,
          ),
      ],
      subtotal: sale.subtotal,
      discount: sale.discount,
      taxAmount: sale.taxAmount,
      total: sale.total,
      paidAmount: sale.paidAmount,
      change: 0,
      customerName: sale.customerId != null ? customerName : null,
      previousBalance: null,
      newBalance: null,
    );

    await showSalePrintDialog(context: context, receipt: receipt);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Sale? _findSale(List<Sale> sales, String id) {
    for (final Sale sale in sales) {
      if (sale.id == id) {
        return sale;
      }
    }
    return null;
  }

  static String _resolveCustomerName(
    List<Customer> customers,
    String? customerId,
  ) {
    if (customerId == null) {
      return 'عميل نقدي';
    }
    for (final Customer customer in customers) {
      if (customer.id == customerId) {
        return customer.name;
      }
    }
    return 'عميل محذوف';
  }
}

// ============================================================================
// Header card
// ============================================================================

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.sale, required this.customerName});

  final Sale sale;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DateFormat dateTimeFormat = DateFormat.yMd('ar_EG').add_Hm();

    final (Color badgeBg, Color badgeFg) = _statusColors(
      scheme,
      sale.status,
    );

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
                    customerName,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
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
                      vertical: 3,
                    ),
                    child: Text(
                      _statusLabel(sale.status),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: badgeFg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  Icons.event_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  dateTimeFormat.format(sale.saleDate.toLocal()),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            if (sale.hasNotes) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                sale.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Actions card
// ============================================================================

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.sale,
    required this.isActing,
    required this.onEdit,
    required this.onConfirm,
    required this.onCancel,
  });

  final Sale sale;
  final bool isActing;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final bool showEdit = sale.canEdit;
    final bool showConfirm = sale.isDraft;
    final bool showCancel = sale.canTransition;

    if (!showEdit && !showConfirm && !showCancel) {
      return const SizedBox.shrink();
    }

    final List<Widget> buttons = <Widget>[];
    if (showEdit) {
      buttons.add(
        Expanded(
          child: AppButton(
            label: 'تعديل',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: isActing ? null : onEdit,
          ),
        ),
      );
    }
    if (showConfirm) {
      buttons.add(
        Expanded(
          child: AppButton(
            label: 'تأكيد',
            icon: Icons.check_circle_outline,
            isLoading: isActing,
            onPressed: isActing ? null : onConfirm,
          ),
        ),
      );
    }
    if (showCancel) {
      buttons.add(
        Expanded(
          child: AppButton(
            label: 'إلغاء الفاتورة',
            icon: Icons.cancel_outlined,
            variant: AppButtonVariant.danger,
            onPressed: isActing ? null : onCancel,
          ),
        ),
      );
    }

    final List<Widget> spaced = <Widget>[];
    for (int i = 0; i < buttons.length; i++) {
      if (i > 0) {
        spaced.add(const SizedBox(width: 8));
      }
      spaced.add(buttons[i]);
    }

    return Row(children: spaced);
  }
}

// ============================================================================
// Items card
// ============================================================================

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({
    required this.items,
    required this.productNames,
    required this.unitNames,
  });

  final List<SaleItem> items;
  final Map<String, String> productNames;
  final Map<String, String> unitNames;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

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
            Text(
              'البنود (${items.length})',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Text(
                'لا توجد بنود.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              for (int i = 0; i < items.length; i++) ...<Widget>[
                _ItemRow(
                  item: items[i],
                  productName:
                      productNames[items[i].productId] ?? 'منتج محذوف',
                  unitName: unitNames[items[i].unitId] ?? 'وحدة',
                ),
                if (i < items.length - 1)
                  const SizedBox(height: 6),
              ],
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

  final SaleItem item;
  final String productName;
  final String unitName;

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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    productName,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${numberFormat.format(item.quantity)} $unitName × '
                    '${moneyFormat.format(item.unitPrice)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              moneyFormat.format(item.lineTotal),
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Totals card
// ============================================================================

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

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
            Text('الإجماليات', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            _line(theme, 'المجموع الفرعي',
                moneyFormat.format(sale.subtotal)),
            const SizedBox(height: 4),
            _line(theme, 'الخصم', moneyFormat.format(sale.discount)),
            const SizedBox(height: 4),
            _line(theme, 'الضريبة', moneyFormat.format(sale.taxAmount)),
            const Divider(height: 20),
            _line(
              theme,
              'الإجمالي',
              moneyFormat.format(sale.total),
              emphasized: true,
            ),
            const SizedBox(height: 4),
            _line(
              theme,
              'المدفوع',
              moneyFormat.format(sale.paidAmount),
            ),
            if (sale.amountDue > 0) ...<Widget>[
              const SizedBox(height: 4),
              _line(
                theme,
                'المتبقي',
                moneyFormat.format(sale.amountDue),
                emphasized: true,
                color: scheme.error,
              ),
            ],
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
    Color? color,
  }) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: emphasized
              ? theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color ?? theme.colorScheme.primary,
                )
              : theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

// ============================================================================
// Returns card
// ============================================================================

/// Lists every sale return recorded against the current sale.
///
/// The card is a no-op when no returns exist yet.
class _ReturnsCard extends ConsumerWidget {
  const _ReturnsCard({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SaleReturn>> returnsAsync =
        ref.watch(saleReturnsProvider(sale.id));

    return returnsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace _) => const SizedBox.shrink(),
      data: (List<SaleReturn> returns) {
        if (returns.isEmpty) {
          return const SizedBox.shrink();
        }

        final ThemeData theme = Theme.of(context);
        final ColorScheme scheme = theme.colorScheme;

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
                    Icon(
                      Icons.assignment_return_outlined,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'المرتجعات (${returns.length})',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < returns.length; i++) ...<Widget>[
                  _ReturnRow(
                    saleReturn: returns[i],
                    onCancel: () => _cancelReturn(
                      context,
                      ref,
                      returns[i],
                    ),
                  ),
                  if (i < returns.length - 1) const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancelReturn(
    BuildContext context,
    WidgetRef ref,
    SaleReturn saleReturn,
  ) async {
    final bool wasConfirmed = saleReturn.isConfirmed;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('إلغاء المرتجع'),
        content: Text(
          wasConfirmed
              ? 'سيتم إلغاء المرتجع وإرجاع الكميات للمخزون، '
                  'وسيُعاد أي رصيد مُخصَّص للعميل.'
              : 'سيتم إلغاء المرتجع. لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'رجوع',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'إلغاء المرتجع',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await ref.read(returnsProvider.notifier).cancelReturn(
            returnId: saleReturn.id,
            saleId: saleReturn.saleId,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم إلغاء المرتجع.')),
        );
    } on ReturnException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_returnFailureMessage(error.type))),
        );
    } on Object {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('تعذّر إلغاء المرتجع. حاول مرة أخرى.'),
          ),
        );
    }
  }
}

// ============================================================================
// Return row
// ============================================================================

class _ReturnRow extends StatelessWidget {
  const _ReturnRow({
    required this.saleReturn,
    required this.onCancel,
  });

  final SaleReturn saleReturn;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final NumberFormat money = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );
    final DateFormat date = DateFormat.yMd('ar_EG');

    final (Color badgeBg, Color badgeFg) =
        _returnStatusColors(scheme, saleReturn.status);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          saleReturn.returnNumber ?? '—',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            _returnStatusLabel(saleReturn.status),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badgeFg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Text(
                        date.format(saleReturn.returnDate.toLocal()),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        money.format(saleReturn.total),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '· ${_refundMethodLabel(saleReturn.refundMethod)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (saleReturn.canTransition)
              IconButton(
                tooltip: 'إلغاء المرتجع',
                icon: const Icon(Icons.cancel_outlined),
                color: scheme.error,
                onPressed: onCancel,
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Localization helpers
// ============================================================================

String _statusLabel(String status) {
  switch (status) {
    case SaleStatus.draft:
      return 'مسودة';
    case SaleStatus.confirmed:
      return 'مؤكدة';
    case SaleStatus.cancelled:
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
    case SaleStatus.draft:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    case SaleStatus.confirmed:
      return (scheme.primaryContainer, scheme.onPrimaryContainer);
    case SaleStatus.cancelled:
      return (scheme.errorContainer, scheme.onErrorContainer);
    default:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
  }
}

String _returnStatusLabel(String status) {
  switch (status) {
    case ReturnStatus.draft:
      return 'مسودة';
    case ReturnStatus.confirmed:
      return 'مؤكد';
    case ReturnStatus.cancelled:
      return 'ملغى';
    default:
      return 'غير معروف';
  }
}

(Color background, Color foreground) _returnStatusColors(
  ColorScheme scheme,
  String status,
) {
  switch (status) {
    case ReturnStatus.draft:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    case ReturnStatus.confirmed:
      return (scheme.primaryContainer, scheme.onPrimaryContainer);
    case ReturnStatus.cancelled:
      return (scheme.errorContainer, scheme.onErrorContainer);
    default:
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
  }
}

String _refundMethodLabel(String method) {
  switch (method) {
    case RefundMethod.cash:
      return 'نقدي';
    case RefundMethod.card:
      return 'بطاقة';
    case RefundMethod.creditNote:
      return 'رصيد';
    case RefundMethod.none:
      return 'بدون استرداد';
    default:
      return method;
  }
}

void _showError(BuildContext context, SaleException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _errorMessage(Object error) {
  if (error is SaleException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(SalesFailureType type) => switch (type) {
      SalesFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      SalesFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      SalesFailureType.notFound =>
        'الفاتورة المطلوبة غير موجودة أو تم حذفها.',
      SalesFailureType.invalidStatusTransition =>
        'لا يمكن إجراء هذه العملية على الفاتورة في حالتها الحالية.',
      SalesFailureType.emptySale =>
        'لا يمكن تأكيد فاتورة بدون بنود. أضف منتجًا واحدًا على الأقل.',
      SalesFailureType.invoiceNumberConflict =>
        'يوجد فاتورة أخرى بنفس الرقم في هذه الشركة.',
      SalesFailureType.customerNotFound =>
        'العميل المختار غير متاح. يرجى إعادة اختياره.',
      SalesFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      SalesFailureType.productNotFound =>
        'أحد المنتجات المختارة غير متاح.',
      SalesFailureType.unitNotFound =>
        'إحدى الوحدات المختارة غير متاحة.',
      SalesFailureType.insufficientStock =>
        'الرصيد غير كافٍ. لا يمكن إتمام الفاتورة.',
      SalesFailureType.invalidPayment =>
        'المبلغ المدفوع أكبر من إجمالي الفاتورة.',
      SalesFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الفواتير. يرجى المحاولة لاحقًا.',
      SalesFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };

String _returnFailureMessage(ReturnFailureType type) {
  switch (type) {
    case ReturnFailureType.network:
      return 'تعذّر الاتصال بالخادم.';
    case ReturnFailureType.unauthorized:
      return 'انتهت صلاحية الجلسة أو لا تملك صلاحية.';
    case ReturnFailureType.notFound:
      return 'المرتجع غير موجود.';
    case ReturnFailureType.saleNotConfirmed:
      return 'الفاتورة الأصلية غير مؤكدة.';
    case ReturnFailureType.emptyReturn:
      return 'المرتجع بدون بنود.';
    case ReturnFailureType.excessiveQuantity:
      return 'الكمية تتجاوز المتاح.';
    case ReturnFailureType.creditNoteRequiresCustomer:
      return 'استرداد الرصيد يتطلب عميلًا.';
    case ReturnFailureType.invalidStatusTransition:
      return 'لا يمكن التعديل في الحالة الحالية.';
    case ReturnFailureType.immutableConfirmedReturn:
      return 'المرتجع المؤكد غير قابل للتعديل.';
    case ReturnFailureType.referenceNotFound:
      return 'أحد المراجع غير موجود.';
    case ReturnFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات.';
    case ReturnFailureType.unknown:
      return 'تعذّر إتمام العملية.';
  }
}
