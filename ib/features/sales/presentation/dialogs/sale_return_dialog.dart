// lib/features/sales/presentation/dialogs/sale_return_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/entities/sale_return.dart';
import '../../domain/repositories/sales_repository.dart';
import '../providers/sales_providers.dart';

/// Opens the "create sale return" dialog for [sale].
///
/// Returns `true` when a return was successfully created, `null` when the
/// operator cancelled. The caller is expected to refresh its own view.
Future<bool?> showSaleReturnDialog({
  required BuildContext context,
  required Sale sale,
  required List<SaleItem> saleItems,
  required List<Customer> customers,
  required List<Product> products,
  required List<Unit> units,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _SaleReturnDialog(
      sale: sale,
      saleItems: saleItems,
      customers: customers,
      products: products,
      units: units,
    ),
  );
}

// ============================================================================
// Dialog
// ============================================================================

class _SaleReturnDialog extends ConsumerStatefulWidget {
  const _SaleReturnDialog({
    required this.sale,
    required this.saleItems,
    required this.customers,
    required this.products,
    required this.units,
  });

  final Sale sale;
  final List<SaleItem> saleItems;
  final List<Customer> customers;
  final List<Product> products;
  final List<Unit> units;

  @override
  ConsumerState<_SaleReturnDialog> createState() => _SaleReturnDialogState();
}

class _SaleReturnDialogState extends ConsumerState<_SaleReturnDialog> {
  final Map<String, TextEditingController> _qtyControllers =
      <String, TextEditingController>{};
  final Map<String, double> _alreadyReturned = <String, double>{};
  late final TextEditingController _notesController;

  String _refundMethod = RefundMethod.creditNote;
  bool _isLoadingReturns = true;
  bool _isSubmitting = false;
  Object? _loadError;
  ReturnFailureType? _serverFailure;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'ar_EG',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final DateFormat _dateFormat = DateFormat.yMd('ar_EG');

  @override
  void initState() {
    super.initState();

    // Default refund method: credit_note when a customer is attached,
    // otherwise cash (credit_note requires a customer on the DB side).
    _refundMethod = widget.sale.hasCustomer
        ? RefundMethod.creditNote
        : RefundMethod.cash;

    _notesController = TextEditingController();

    for (final SaleItem item in widget.saleItems) {
      _qtyControllers[item.id] = TextEditingController(text: '0');
    }

    _loadExistingReturns();
  }

  @override
  void dispose() {
    for (final TextEditingController c in _qtyControllers.values) {
      c.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Load already-returned quantities
  // ---------------------------------------------------------------------------

  Future<void> _loadExistingReturns() async {
    try {
      final ReturnsRepository repo =
          ref.read(returnsRepositoryProvider);

      final List<SaleReturn> returns =
          await repo.listReturnsForSale(widget.sale.id);

      final Map<String, double> map = <String, double>{};
      for (final SaleReturn r in returns) {
        if (r.isCancelled) {
          continue;
        }
        final List<SaleReturnItem> items =
            await repo.listReturnItems(r.id);
        for (final SaleReturnItem it in items) {
          map[it.saleItemId] =
              (map[it.saleItemId] ?? 0) + it.quantity;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _alreadyReturned
          ..clear()
          ..addAll(map);
        _isLoadingReturns = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _isLoadingReturns = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------

  /// The maximum quantity that can still be returned for [saleItem].
  double _remainingFor(SaleItem saleItem) {
    final double already = _alreadyReturned[saleItem.id] ?? 0;
    final double remaining = saleItem.quantity - already;
    return remaining < 0 ? 0 : remaining;
  }

  /// Selected quantity for a sale item (0 when blank/invalid).
  double _qtyFor(SaleItem saleItem) {
    final TextEditingController? c = _qtyControllers[saleItem.id];
    if (c == null) {
      return 0;
    }
    final double parsed = double.tryParse(c.text.trim()) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  /// Total amount of the return (subtotal; discount/tax are always 0).
  double get _returnTotal {
    double sum = 0;
    for (final SaleItem item in widget.saleItems) {
      sum += _qtyFor(item) * item.unitPrice;
    }
    return sum;
  }

  bool get _hasAnyQuantity =>
      widget.saleItems.any((SaleItem i) => _qtyFor(i) > 0);

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _validationError() {
    if (!widget.sale.isConfirmed) {
      return 'لا يمكن إنشاء مرتجع لفاتورة غير مؤكدة.';
    }
    if (!_hasAnyQuantity) {
      return 'اختر كمية لإرجاعها من بند واحد على الأقل.';
    }
    for (final SaleItem item in widget.saleItems) {
      final double qty = _qtyFor(item);
      final double remaining = _remainingFor(item);
      if (qty > remaining) {
        return 'الكمية المُرجَعة أكبر من المتاح للإرجاع.';
      }
    }
    if (_refundMethod == RefundMethod.creditNote &&
        !widget.sale.hasCustomer) {
      return 'استرداد بالرصيد يتطلب عميلًا مسجلًا.';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit({required bool andConfirm}) async {
    FocusScope.of(context).unfocus();

    if (_validationError() != null) {
      return;
    }

    final CompanyContextState contextState =
        ref.read(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;
    if (branchId == null) {
      setState(() => _serverFailure = ReturnFailureType.unauthorized);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serverFailure = null;
    });

    final List<SaleReturnItemDraft> drafts = <SaleReturnItemDraft>[];
    for (final SaleItem item in widget.saleItems) {
      final double qty = _qtyFor(item);
      if (qty <= 0) {
        continue;
      }
      drafts.add(
        SaleReturnItemDraft(
          saleItemId: item.id,
          productId: item.productId,
          unitId: item.unitId,
          quantity: qty,
          unitPrice: item.unitPrice,
        ),
      );
    }

    final String notes = _notesController.text.trim();

    try {
      final ReturnsNotifier notifier =
          ref.read(returnsProvider.notifier);

      final SaleReturn created = await notifier.createReturn(
        branchId: branchId,
        saleId: widget.sale.id,
        customerId: widget.sale.customerId,
        returnDate: DateTime.now(),
        items: drafts,
        refundMethod: _refundMethod,
        notes: notes.isEmpty ? null : notes,
      );

      if (andConfirm) {
        await notifier.confirmReturn(
          returnId: created.id,
          saleId: widget.sale.id,
        );
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on ReturnException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _serverFailure = error.type;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _serverFailure = ReturnFailureType.unknown;
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

    if (_isLoadingReturns) {
      return AlertDialog(
        content: const SizedBox(
          width: 480,
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: <Widget>[
          AppButton(
            label: 'إغلاق',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    if (_loadError != null) {
      return AlertDialog(
        title: const Text('تعذّر تحميل بيانات المرتجع'),
        content: Text(_errorMessage(_loadError!)),
        actions: <Widget>[
          AppButton(
            label: 'إغلاق',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: 'إعادة المحاولة',
            onPressed: () {
              setState(() {
                _isLoadingReturns = true;
                _loadError = null;
              });
              _loadExistingReturns();
            },
          ),
        ],
      );
    }

    final String? validationError = _validationError();
    final String? failureMessage = _serverFailure != null
        ? _failureMessageFor(_serverFailure!)
        : null;
    final String? displayError = failureMessage ?? validationError;
    final bool canSubmit = !_isSubmitting && validationError == null;

    final Map<String, String> productNames = <String, String>{
      for (final Product p in widget.products) p.id: p.name,
    };
    final Map<String, String> unitNames = <String, String>{
      for (final Unit u in widget.units) u.id: u.name,
    };

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.assignment_return_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('إنشاء مرتجع')),
          IconButton(
            onPressed: _isSubmitting
                ? null
                : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ---- Sale summary ----
              _SaleSummaryCard(
                sale: widget.sale,
                dateFormat: _dateFormat,
              ),
              const SizedBox(height: 12),

              // ---- Items ----
              Text(
                'اختر الكميات المُرجَعة',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final SaleItem item in widget.saleItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ReturnItemRow(
                    saleItem: item,
                    productName:
                        productNames[item.productId] ?? 'منتج محذوف',
                    unitName: unitNames[item.unitId] ?? 'وحدة',
                    remaining: _remainingFor(item),
                    controller: _qtyControllers[item.id]!,
                    enabled: !_isSubmitting,
                    money: _money,
                    onChanged: () => setState(() {}),
                  ),
                ),

              const SizedBox(height: 16),

              // ---- Refund method ----
              Text('طريقة الاسترداد', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _RefundMethodSelector(
                value: _refundMethod,
                enabled: !_isSubmitting,
                hasCustomer: widget.sale.hasCustomer,
                onChanged: (String v) {
                  setState(() => _refundMethod = v);
                },
              ),

              const SizedBox(height: 12),

              // ---- Notes ----
              AppTextField(
                controller: _notesController,
                label: 'ملاحظات — اختياري',
                enabled: !_isSubmitting,
                maxLines: 2,
              ),

              if (displayError != null) ...<Widget>[
                const SizedBox(height: 12),
                _ErrorBanner(message: displayError),
              ],

              const SizedBox(height: 12),

              // ---- Total preview ----
              _TotalPreview(
                total: _returnTotal,
                money: _money,
                theme: theme,
                scheme: scheme,
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    label: 'إلغاء',
                    variant: AppButtonVariant.text,
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    label: 'حفظ كمسودة',
                    variant: AppButtonVariant.secondary,
                    isLoading: _isSubmitting,
                    onPressed: canSubmit
                        ? () => _submit(andConfirm: false)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'حفظ وتأكيد',
              icon: Icons.check_circle_outline,
              expanded: true,
              size: AppButtonSize.large,
              isLoading: _isSubmitting,
              onPressed: canSubmit
                  ? () => _submit(andConfirm: true)
                  : null,
            ),
          ],
        ),
      ],
      backgroundColor: scheme.surface,
      scrollable: false,
    );
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _SaleSummaryCard extends StatelessWidget {
  const _SaleSummaryCard({
    required this.sale,
    required this.dateFormat,
  });

  final Sale sale;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.receipt_long_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sale.invoiceNumber ?? 'بدون رقم',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  dateFormat.format(sale.saleDate.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnItemRow extends StatelessWidget {
  const _ReturnItemRow({
    required this.saleItem,
    required this.productName,
    required this.unitName,
    required this.remaining,
    required this.controller,
    required this.enabled,
    required this.money,
    required this.onChanged,
  });

  final SaleItem saleItem;
  final String productName;
  final String unitName;
  final double remaining;
  final TextEditingController controller;
  final bool enabled;
  final NumberFormat money;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool soldOut = remaining <= 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: soldOut
            ? Border.all(color: scheme.outlineVariant)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    productName,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${_fmt(saleItem.quantity)} $unitName',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'السعر: ${money.format(saleItem.unitPrice)} · '
                    'المتاح للإرجاع: ${_fmt(remaining)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  height: 40,
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !soldOut,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      hintText: '0',
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

class _RefundMethodSelector extends StatelessWidget {
  const _RefundMethodSelector({
    required this.value,
    required this.enabled,
    required this.hasCustomer,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final bool hasCustomer;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // `credit_note` requires a customer; disable it when the sale is a
    // cash sale.
    final bool creditNoteEnabled = hasCustomer;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _chip(
            context,
            label: 'استرداد نقدي',
            value: RefundMethod.cash,
            enabled: enabled,
          ),
          const SizedBox(width: 6),
          _chip(
            context,
            label: 'استرداد بالبطاقة',
            value: RefundMethod.card,
            enabled: enabled,
          ),
          const SizedBox(width: 6),
          _chip(
            context,
            label: 'خصم من الرصيد',
            value: RefundMethod.creditNote,
            enabled: enabled && creditNoteEnabled,
            tooltip: creditNoteEnabled
                ? null
                : 'يتطلب عميلًا مسجلًا على الفاتورة',
          ),
          const SizedBox(width: 6),
          _chip(
            context,
            label: 'بدون استرداد',
            value: RefundMethod.none,
            enabled: enabled,
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required String value,
    required bool enabled,
    String? tooltip,
  }) {
    final Widget chip = ChoiceChip(
      label: Text(label),
      selected: this.value == value,
      onSelected: enabled ? (_) => onChanged(value) : null,
    );
    if (tooltip == null) {
      return chip;
    }
    return Tooltip(message: tooltip, child: chip);
  }
}

class _TotalPreview extends StatelessWidget {
  const _TotalPreview({
    required this.total,
    required this.money,
    required this.theme,
    required this.scheme,
  });

  final double total;
  final NumberFormat money;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            Text(
              'إجمالي المرتجع',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              money.format(total),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: scheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Localization
// ============================================================================

String _errorMessage(Object error) {
  if (error is ReturnException) {
    return _failureMessageFor(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessageFor(ReturnFailureType type) {
  switch (type) {
    case ReturnFailureType.network:
      return 'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.';
    case ReturnFailureType.unauthorized:
      return 'انتهت صلاحية الجلسة أو لا تملك صلاحية.';
    case ReturnFailureType.notFound:
      return 'المرتجع أو الفاتورة الأصلية غير موجودة.';
    case ReturnFailureType.saleNotConfirmed:
      return 'لا يمكن إنشاء مرتجع لفاتورة غير مؤكدة.';
    case ReturnFailureType.emptyReturn:
      return 'لا يمكن حفظ مرتجع بدون بنود.';
    case ReturnFailureType.excessiveQuantity:
      return 'الكمية المُرجَعة أكبر من المتاح للإرجاع.';
    case ReturnFailureType.creditNoteRequiresCustomer:
      return 'خصم من الرصيد يتطلب عميلًا مسجلًا على الفاتورة.';
    case ReturnFailureType.invalidStatusTransition:
      return 'لا يمكن تعديل المرتجع في حالته الحالية.';
    case ReturnFailureType.immutableConfirmedReturn:
      return 'لا يمكن تعديل مرتجع مؤكد (باستثناء الملاحظات).';
    case ReturnFailureType.referenceNotFound:
      return 'أحد البنود المرجعية غير موجود.';
    case ReturnFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.';
    case ReturnFailureType.unknown:
      return 'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.';
  }
}
