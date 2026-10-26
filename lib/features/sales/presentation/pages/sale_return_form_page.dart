// lib/features/sales/presentation/pages/sale_return_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

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

class _ReturnCartLine {
  final Product product;
  final Unit unit;
  double quantity;
  double unitPrice;

  _ReturnCartLine({
    required this.product,
    required this.unit,
    this.quantity = 1,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;
}

class _SaleReturnFormPageState extends ConsumerState<SaleReturnFormPage> {
  final TextEditingController _searchController = TextEditingController();
  final List<_ReturnCartLine> _cart = [];
  String _searchQuery = '';
  String? _selectedCustomerId;
  String _refundMethod = RefundMethod.cash;
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _totalAmount => _cart.fold(0, (sum, line) => sum + line.total);

  void _addProduct(Product p) {
    final units = ref.read(unitsProvider).value ?? [];
    Unit? defaultUnit;
    for (final u in units) {
      if (u.id == p.defaultUnitId) {
        defaultUnit = u;
        break;
      }
    }
    if (defaultUnit == null) {
      _snack('وحدة المنتج غير متاحة.');
      return;
    }

    final existingIndex = _cart.indexWhere((l) => l.product.id == p.id && l.unit.id == defaultUnit!.id);
    if (existingIndex >= 0) {
      setState(() => _cart[existingIndex].quantity += 1);
    } else {
      setState(() {
        _cart.add(_ReturnCartLine(
          product: p,
          unit: defaultUnit!,
          unitPrice: p.sellingPrice, // افتراضي: سعر البيع
        ));
      });
    }
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _removeLine(int index) {
    setState(() => _cart.removeAt(index));
  }

  Future<void> _submit({required bool andConfirm}) async {
    if (_cart.isEmpty) {
      _snack('أضف صنفاً واحداً على الأقل.');
      return;
    }

    if (_refundMethod == RefundMethod.creditNote && _selectedCustomerId == null) {
      _snack('الاسترداد كرصيد يتطلب اختيار عميل.');
      return;
    }

    setState(() => _isSubmitting = true);

    final contextState = ref.read(companyContextProvider);
    final companyId = contextState.currentCompany?.id;
    final branchId = contextState.currentBranch?.id;

    if (companyId == null || branchId == null) {
      _snack('الشركة أو الفرع غير محدد.');
      setState(() => _isSubmitting = false);
      return;
    }

    final drafts = _cart.map((line) => SaleReturnItemDraft(
      saleItemId: const Uuid().v4(), // ⚠️ يتطلب أن يسمح الـ DB بـ NULL أو UUID وهمي
      productId: line.product.id,
      unitId: line.unit.id,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
    )).toList();

    try {
      final repo = ref.read(returnsRepositoryProvider);
      final created = await repo.createReturn(
        companyId: companyId,
        branchId: branchId,
        saleId: const Uuid().v4(), // ⚠️ يتطلب أن يسمح الـ DB بـ NULL أو UUID وهمي
        customerId: _selectedCustomerId,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final customers = ref.watch(customersProvider).value ?? const <Customer>[];
    final units = ref.watch(unitsProvider).value ?? const <Unit>[];

    // البحث عن المنتجات
    final filteredProducts = _searchQuery.trim().isEmpty
        ? const <Product>[]
        : products.where((p) {
            final q = _searchQuery.toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                   (p.sku ?? '').toLowerCase().contains(q) ||
                   (p.barcode ?? '').toLowerCase().contains(q);
          }).take(10).toList();

    return AppShell(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('إنشاء مرتجع'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. البحث عن المنتجات
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                AppTextField(
                  controller: _searchController,
                  hint: 'ابحث عن صنف لإرجاعه (بالاسم أو الباركود)',
                  prefixIcon: Icons.search,
                  suffixIcon: _searchQuery.isEmpty ? null : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                if (_searchQuery.isNotEmpty && filteredProducts.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final p = filteredProducts[index];
                        return ListTile(
                          title: Text(p.name),
                          subtitle: Text('${p.sellingPrice} ج.م'),
                          onTap: () => _addProduct(p),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // 2. سلة المرتجع
          Expanded(
            child: _cart.isEmpty
                ? const AppEmptyView(
                    icon: Icons.assignment_return_outlined,
                    title: 'سلة المرتجع فارغة',
                    message: 'ابحث عن صنف في الأعلى لإضافته إلى المرتجع.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final line = _cart[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(line.product.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 60,
                                        child: TextFormField(
                                          initialValue: line.quantity.toString(),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(isDense: true, labelText: 'الكمية'),
                                          onChanged: (v) {
                                            final val = double.tryParse(v) ?? 1;
                                            setState(() => line.quantity = val > 0 ? val : 1);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 80,
                                        child: TextFormField(
                                          initialValue: line.unitPrice.toString(),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(isDense: true, labelText: 'السعر'),
                                          onChanged: (v) {
                                            final val = double.tryParse(v) ?? 0;
                                            setState(() => line.unitPrice = val >= 0 ? val : 0);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text('= ${AppFormatters.money(line.total)}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _removeLine(index),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // 3. لوحة التحكم السفلية
          Container(
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
                          initialValue: _selectedCustomerId,
                          decoration: const InputDecoration(labelText: 'العميل (اختياري)', isDense: true, border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('بدون عميل')),
                            ...customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                          ],
                          onChanged: _isSubmitting ? null : (v) => setState(() => _selectedCustomerId = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _refundMethod,
                          decoration: const InputDecoration(labelText: 'طريقة الاسترداد', isDense: true, border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: RefundMethod.cash, child: Text('نقدي')),
                            DropdownMenuItem(value: RefundMethod.card, child: Text('بطاقة')),
                            DropdownMenuItem(value: RefundMethod.creditNote, child: Text('رصيد (خصم من الحساب)')),
                            DropdownMenuItem(value: RefundMethod.none, child: Text('بدون استرداد')),
                          ],
                          onChanged: _isSubmitting ? null : (v) => v != null ? setState(() => _refundMethod = v) : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('إجمالي المرتجع', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(AppFormatters.money(_totalAmount), style: theme.textTheme.headlineSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'حفظ كمسودة',
                          variant: AppButtonVariant.secondary,
                          onPressed: _cart.isNotEmpty && !_isSubmitting ? () => _submit(andConfirm: false) : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'حفظ وتأكيد',
                          isLoading: _isSubmitting,
                          onPressed: _cart.isNotEmpty && !_isSubmitting ? () => _submit(andConfirm: true) : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
