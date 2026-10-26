// lib/features/sales/presentation/pages/sale_return_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../products/domain/entities/product.dart';
import '../../../products/domain/entities/unit.dart';
import '../../../products/presentation/providers/product_providers.dart';
import '../../../products/presentation/providers/unit_providers.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/entities/sale_return.dart';
import '../../domain/repositories/sales_repository.dart';
import '../providers/sales_providers.dart';

class SaleReturnFormPage extends ConsumerStatefulWidget {
  const SaleReturnFormPage({super.key});

  @override
  ConsumerState<SaleReturnFormPage> createState() => _SaleReturnFormPageState();
}

class _SaleReturnFormPageState extends ConsumerState<SaleReturnFormPage> {
  Sale? _selectedSale;
  List<SaleItem> _saleItems = [];
  final Map<String, double> _returnQuantities = {};
  String _refundMethod = RefundMethod.cash;
  final TextEditingController _notesController = TextEditingController();
  bool _isLoadingItems = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Calculations
  // ---------------------------------------------------------------------------

  double get _totalReturnAmount {
    double total = 0;
    for (final item in _saleItems) {
      final qty = _returnQuantities[item.id] ?? 0;
      total += qty * item.unitPrice;
    }
    return total;
  }

  int get _selectedItemsCount {
    return _saleItems.where((item) => (_returnQuantities[item.id] ?? 0) > 0).length;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _pickSale() async {
    final salesAsync = ref.read(salesProvider);
    final sales = salesAsync.value?.where((s) => s.isConfirmed).toList() ?? [];
    
    if (sales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد فواتير مبيعات مؤكدة متاحة.')),
      );
      return;
    }

    final picked = await showModalBottomSheet<Sale>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _SalePickerSheet(sales: sales),
    );

    if (picked != null) {
      setState(() {
        _selectedSale = picked;
        _isLoadingItems = true;
        _returnQuantities.clear();
      });
      try {
        final items = await ref.read(salesRepositoryProvider).listSaleItems(picked.id);
        setState(() {
          _saleItems = items;
        });
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر تحميل بنود الفاتورة: $e')),
        );
      } finally {
        if (mounted) setState(() => _isLoadingItems = false);
      }
    }
  }

  void _returnAll() {
    setState(() {
      for (final item in _saleItems) {
        _returnQuantities[item.id] = item.quantity;
      }
    });
  }

  Future<void> _submit({required bool andConfirm}) async {
    if (_selectedSale == null) {
      _snack('يرجى اختيار فاتورة أولاً.');
      return;
    }
    if (_selectedItemsCount == 0) {
      _snack('يرجى تحديد كمية مرتجعة لصنف واحد على الأقل.');
      return;
    }
    if (_refundMethod == RefundMethod.creditNote && _selectedSale!.customerId == null) {
      _snack('لا يمكن الاسترداد كرصيد لأن الفاتورة بدون عميل.');
      return;
    }

    setState(() => _isSubmitting = true);

    final CompanyContextState contextState = ref.read(companyContextProvider);
    final String? companyId = contextState.currentCompany?.id;
    final String? branchId = contextState.currentBranch?.id;

    if (companyId == null || branchId == null) {
      _snack('الشركة أو الفرع غير محدد.');
      setState(() => _isSubmitting = false);
      return;
    }

    final List<SaleReturnItemDraft> drafts = [];
    for (final item in _saleItems) {
      final qty = _returnQuantities[item.id] ?? 0;
      if (qty > 0) {
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
    }

    try {
      final repo = ref.read(returnsRepositoryProvider);
      final created = await repo.createReturn(
        companyId: companyId,
        branchId: branchId,
        saleId: _selectedSale!.id,
        customerId: _selectedSale!.customerId,
        returnDate: DateTime.now(),
        items: drafts,
        refundMethod: _refundMethod,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (andConfirm) {
        await repo.confirmReturn(created.id);
      }

      ref.invalidate(returnsProvider);
      
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(andConfirm ? 'تم حفظ وتأكيد المرتجع.' : 'تم حفظ المرتجع كمسودة.')),
      );
    } on ReturnException catch (e) {
      _snack(_failureMessage(e.type));
    } on Object {
      _snack('تعذّر إتمام العملية. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final units = ref.watch(unitsProvider).value ?? const <Unit>[];
    
    final Map<String, String> productNames = {
      for (final p in products) p.id: p.name,
    };
    final Map<String, String> unitNames = {
      for (final u in units) u.id: u.name,
    };

    return AppShell(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('إنشاء فاتورة مرتجع'),
        actions: [
          if (_selectedSale != null)
            TextButton.icon(
              onPressed: _isSubmitting ? null : () => _pickSale(),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('تغيير الفاتورة'),
            )
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedSale == null)
            Expanded(
              child: AppEmptyView(
                icon: Icons.receipt_long_outlined,
                title: 'لم يتم اختيار فاتورة',
                message: 'اختر الفاتورة الأصلية لعرض أصنافها وإنشاء المرتجع.',
                action: AppButton(
                  label: 'اختيار فاتورة مبيعات',
                  icon: Icons.search,
                  onPressed: _pickSale,
                ),
              ),
            )
          else ...[
            _SaleHeaderCard(sale: _selectedSale!),
            const Divider(height: 1),
            if (_isLoadingItems)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_saleItems.isEmpty)
              const Expanded(
                child: Center(child: Text('هذه الفاتورة لا تحتوي على بنود.')),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('بنود الفاتورة', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: _returnAll,
                      child: const Text('إرجاع الكل'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _saleItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _saleItems[index];
                    return _ReturnItemRow(
                      item: item,
                      productName: productNames[item.productId] ?? 'منتج محذوف',
                      unitName: unitNames[item.unitId] ?? 'وحدة',
                      returnQty: _returnQuantities[item.id] ?? 0,
                      onQtyChanged: (qty) {
                        setState(() {
                          _returnQuantities[item.id] = qty;
                        });
                      },
                    );
                  },
                ),
              ),
              _BottomPanel(
                total: _totalReturnAmount,
                refundMethod: _refundMethod,
                notesController: _notesController,
                isSubmitting: _isSubmitting,
                canSave: _selectedItemsCount > 0,
                onRefundMethodChanged: (val) => setState(() => _refundMethod = val),
                onSaveDraft: () => _submit(andConfirm: false),
                onSaveAndConfirm: () => _submit(andConfirm: true),
              ),
            ]
          ]
        ],
      ),
    );
  }

  String _failureMessage(ReturnFailureType type) {
    switch (type) {
      case ReturnFailureType.network: return 'تعذّر الاتصال بالخادم.';
      case ReturnFailureType.unauthorized: return 'انتهت صلاحية الجلسة.';
      case ReturnFailureType.notFound: return 'المرتجع غير موجود.';
      case ReturnFailureType.saleNotConfirmed: return 'الفاتورة الأصلية غير مؤكدة.';
      case ReturnFailureType.emptyReturn: return 'المرتجع بدون بنود.';
      case ReturnFailureType.excessiveQuantity: return 'الكمية تتجاوز المتاح.';
      case ReturnFailureType.creditNoteRequiresCustomer: return 'استرداد الرصيد يتطلب عميلاً.';
      case ReturnFailureType.invalidStatusTransition: return 'لا يمكن التعديل في الحالة الحالية.';
      case ReturnFailureType.immutableConfirmedReturn: return 'المرتجع المؤكد غير قابل للتعديل.';
      case ReturnFailureType.referenceNotFound: return 'أحد المراجع غير موجود.';
      case ReturnFailureType.invalidResponse: return 'تعذّر قراءة البيانات.';
      case ReturnFailureType.unknown: return 'تعذّر إتمام العملية.';
    }
  }
}

// ============================================================================
// Sale Header Card
// ============================================================================

class _SaleHeaderCard extends StatelessWidget {
  const _SaleHeaderCard({required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.receipt_long_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('فاتورة: ${sale.invoiceNumber ?? "—"}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('التاريخ: ${AppFormatters.date(sale.saleDate)}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text(AppFormatters.money(sale.total), style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ============================================================================
// Return Item Row
// ============================================================================

class _ReturnItemRow extends StatelessWidget {
  const _ReturnItemRow({
    required this.item,
    required this.productName,
    required this.unitName,
    required this.returnQty,
    required this.onQtyChanged,
  });

  final SaleItem item;
  final String productName;
  final String unitName;
  final double returnQty;
  final ValueChanged<double> onQtyChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(productName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'المباع: ${AppFormatters.quantity(item.quantity)} $unitName · السعر: ${AppFormatters.money(item.unitPrice)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: returnQty > 0 ? AppFormatters.quantity(returnQty) : '',
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(
                isDense: true,
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (val) {
                final parsed = double.tryParse(val) ?? 0;
                // منع تجاوز الكمية المباعة
                if (parsed > item.quantity) {
                  onQtyChanged(item.quantity);
                  // يمكن إضافة إشعار هنا
                } else {
                  onQtyChanged(parsed);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Bottom Panel
// ============================================================================

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.total,
    required this.refundMethod,
    required this.notesController,
    required this.isSubmitting,
    required this.canSave,
    required this.onRefundMethodChanged,
    required this.onSaveDraft,
    required this.onSaveAndConfirm,
  });

  final double total;
  final String refundMethod;
  final TextEditingController notesController;
  final bool isSubmitting;
  final bool canSave;
  final ValueChanged<String> onRefundMethodChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onSaveAndConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: refundMethod,
                    decoration: const InputDecoration(
                      labelText: 'طريقة الاسترداد',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: RefundMethod.cash, child: Text('نقدي')),
                      DropdownMenuItem(value: RefundMethod.card, child: Text('بطاقة')),
                      DropdownMenuItem(value: RefundMethod.creditNote, child: Text('رصيد (خصم من الحساب)')),
                      DropdownMenuItem(value: RefundMethod.none, child: Text('بدون استرداد')),
                    ],
                    onChanged: isSubmitting ? null : (v) => v != null ? onRefundMethodChanged(v) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('إجمالي المرتجع', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text(AppFormatters.money(total), style: theme.textTheme.headlineSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'حفظ كمسودة',
                    variant: AppButtonVariant.secondary,
                    onPressed: canSave && !isSubmitting ? onSaveDraft : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'حفظ وتأكيد',
                    isLoading: isSubmitting,
                    onPressed: canSave && !isSubmitting ? onSaveAndConfirm : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Sale Picker Sheet
// ============================================================================

class _SalePickerSheet extends StatelessWidget {
  const _SalePickerSheet({required this.sales});
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('اختر فاتورة مبيعات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: sales.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final sale = sales[index];
                return ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(sale.invoiceNumber ?? 'بدون رقم'),
                  subtitle: Text('${AppFormatters.date(sale.saleDate)} · العميل: ${sale.customerName ?? "بدون عميل"}'),
                  trailing: Text(AppFormatters.money(sale.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.of(context).pop(sale),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
