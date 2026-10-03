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
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../../suppliers/domain/entities/supplier.dart';
import '../../../suppliers/presentation/providers/supplier_providers.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/purchase_item.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../providers/purchase_providers.dart';

/// Read-only view of a single purchase order.
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
    final AsyncValue<List<Supplier>> suppliersAsync =
        ref.watch(suppliersProvider);
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    final bool anyLoading = purchasesAsync.isLoading ||
        itemsAsync.isLoading ||
        suppliersAsync.isLoading ||
        productsAsync.isLoading ||
        unitsAsync.isLoading;

    final Object? firstError = purchasesAsync.error ??
        itemsAsync.error ??
        suppliersAsync.error ??
        productsAsync.error ??
        unitsAsync.error;

    return AppShell(
      appBar: AppBar(
        title: const Text('تفاصيل الفاتورة'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            onPressed: anyLoading || _isActing
                ? null
                : () {
                    ref.invalidate(purchasesProvider);
                    ref.invalidate(purchaseItemsProvider(id));
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
