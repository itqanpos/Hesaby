// lib/features/sales/presentation/pages/sale_return_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  _ReturnCartLine({
    required this.product,
    required this.unit,
    this.quantity = 1,
    required this.unitPrice,
  });

  final Product product;
  final Unit unit;
  double quantity;
  double unitPrice;

  String get key => '${product.id}::${unit.id}';
  double get lineTotal => quantity * unitPrice;
}

class _SaleReturnFormPageState extends ConsumerState<SaleReturnFormPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<_ReturnCartLine> _cart = <_ReturnCartLine>[];
  String _searchQuery = '';
  String? _selectedCustomerId;
  String _refundMethod = RefundMethod.cash;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _totalAmount => _cart.fold<double>(
        0,
        (double s, _ReturnCartLine l) => s + l.lineTotal,
      );

  void _addProduct(Product product) {
    final List<Unit> units =
        ref.read(unitsProvider).valueOrNull ?? const <Unit>[];
    Unit? defaultUnit;
    for (final Unit u in units) {
      if (u.id == product.defaultUnitId) {
        defaultUnit = u;
        break;
      }
    }
    if (defaultUnit == null) {
      _snack('وحدة المنتج غير متاحة.');
      return;
    }

    final String key = '${product.id}::${defaultUnit.id}';
    final int existing = _cart.indexWhere((_ReturnCartLine l) => l.key == key);
    if (existing >= 0) {
      setState(() => _cart[existing].quantity += 1);
    } else {
      setState(() {
        _cart.add(_ReturnCartLine(
          product: product,
          unit: defaultUnit!,
          unitPrice: product.sellingPrice,
        ));
      });
    }
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _removeLine(int index) => setState(() => _cart.removeAt(index));

  void _updateQuantity(int index, double qty) {
    if (qty <= 0) return;
    setState(() => _cart[index].quantity = qty);
  }

  void _updatePrice(int index, double price) {
    if (price < 0) return;
    setState(() => _cart[index].unitPrice = price);
  }

  Future<void> _submit({required bool andConfirm}) async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();

    if (_cart.isEmpty) {
      _snack('أضف صنفاً واحداً على الأقل.');
      return;
    }
    if (_refundMethod == RefundMethod.creditNote && _selectedCustomerId == null) {
      _snack('استرداد الرصيد يتطلب اختيار عميل.');
      return;
    }

    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String? companyId = ctx.currentCompany?.id;
    final String? branchId = ctx.currentBranch?.id;

    if (companyId == null || branchId == null) {
      _snack('الشركة أو الفرع غير محدد.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final List<SaleReturnItemDraft> drafts = <SaleReturnItemDraft>[
        for (final _ReturnCartLine line in _cart)
          SaleReturnItemDraft(
            saleItemId: null, // ⬅️ مرتجع مستقل
            productId: line.product.id,
            unitId: line.unit.id,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
          ),
      ];

      final ReturnsRepository repo = ref.read(returnsRepositoryProvider);

      final SaleReturn created = await repo.createReturn(
        companyId: companyId,
        branchId: branchId,
        saleId: null, // ⬅️ مرتجع مستقل
        customerId: _selectedCustomerId,
        returnDate: DateTime.now(),
        items: drafts,
        refundMethod: _refundMethod,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (andConfirm) {
        await repo.confirmReturn(created.id);
      }

      ref.invalidate(returnsProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              andConfirm ? 'تم حفظ وتأكيد المرتجع.' : 'تم حفظ المرتجع كمسودة.',
            ),
          ),
        );
    } on ReturnException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack(_failureMessage(error.type));
    } on Object {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack('تعذّر إتمام العملية. حاول مرة أخرى.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final List<Product> products =
        ref.watch(productsProvider).valueOrNull ?? const <Product>[];
    final List<Unit> units =
        ref.watch(unitsProvider).valueOrNull ?? const <Unit>[];
    final List<Customer> customers =
        ref.watch(customersProvider).valueOrNull ?? const <Customer>[];

    final Map<String, String> unitNames = <String, String>{
      for (final Unit u in units) u.id: u.name,
    };

    final String trimmed = _searchQuery.trim().toLowerCase();
    final List<Product> suggestions = trimmed.isEmpty
        ? const <Product>[]
        : products.where((Product p) {
            final String name = p.name.toLowerCase();
            final String sku = (p.sku ?? '').toLowerCase();
            final String barcode = (p.barcode ?? '').toLowerCase();
            return name.contains(trimmed) ||
                sku.contains(trimmed) ||
                barcode.contains(trimmed);
          }).take(8).toList(growable: false);

    return AppShell(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'رجوع',
          icon: const Icon(Icons.arrow_back),
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text('مرتجع جديد'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppTextField(
              controller: _searchController,
              hint: 'ابحث عن صنف بالاسم أو الباركود',
              prefixIcon: Icons.search,
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
              onChanged: (String v) => setState(() => _searchQuery = v),
            ),
          ),

          if (trimmed.isNotEmpty && suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: suggestions.length,
                itemBuilder: (BuildContext context, int index) {
                  final Product p = suggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${AppFormatters.money(p.sellingPrice)} · ${unitNames[p.defaultUnitId] ?? 'وحدة'}'),
                    onTap: () => _addProduct(p),
                  );
                },
              ),
            ),

          const SizedBox(height: 8),

          Expanded(
            child: _cart.isEmpty
                ? const AppEmptyView(
                    icon: Icons.assignment_return_outlined,
                    title: 'سلة المرتجع فارغة',
                    message: 'ابحث عن صنف في الأعلى لإضافته إلى المرتجع.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final _ReturnCartLine line = _cart[index];
                      return _ReturnLineTile(
                        line: line,
                        unitName: unitNames[line.unit.id] ?? line.unit.name,
                        onQuantityChanged: (double q) => _updateQuantity(index, q),
                        onPriceChanged: (double p) => _updatePrice(index, p),
                        onRemove: () => _removeLine(index),
                      );
                    },
                  ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedCustomerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'العميل (اختياري)',
                      prefixIcon: Icon(Icons.person_outline, size: 18),
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون عميل'),
                      ),
                      for (final Customer c in customers)
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name),
                        ),
                    ],
                    onChanged: _isSubmitting ? null : (String? v) => setState(() => _selectedCustomerId = v),
                  ),
                  const SizedBox(height: 8),

                  DropdownButtonFormField<String>(
                    initialValue: _refundMethod,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'طريقة الاسترداد',
                      prefixIcon: Icon(Icons.payments_outlined, size: 18),
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: RefundMethod.cash, child: Text('نقدي')),
                      DropdownMenuItem<String>(value: RefundMethod.card, child: Text('بطاقة')),
                      DropdownMenuItem<String>(value: RefundMethod.creditNote, child: Text('رصيد (خصم من حساب العميل)')),
                      DropdownMenuItem<String>(value: RefundMethod.none, child: Text('بدون استرداد')),
                    ],
                    onChanged: _isSubmitting ? null : (String? v) {
                      if (v != null) setState(() => _refundMethod = v);
                    },
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _notesController,
                    enabled: !_isSubmitting,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: <Widget>[
                      Text('إجمالي المرتجع', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(AppFormatters.money(_totalAmount), style: theme.textTheme.titleLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppButton(
                          label: 'حفظ كمسودة',
                          icon: Icons.save_outlined,
                          variant: AppButtonVariant.secondary,
                          onPressed: _isSubmitting || _cart.isEmpty ? null : () => _submit(andConfirm: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'حفظ وتأكيد',
                          icon: Icons.check_circle_outline,
                          isLoading: _isSubmitting,
                          onPressed: _isSubmitting || _cart.isEmpty ? null : () => _submit(andConfirm: true),
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

  static String _failureMessage(ReturnFailureType type) => switch (type) {
        ReturnFailureType.network => 'تعذّر الاتصال بالخادم.',
        ReturnFailureType.unauthorized => 'انتهت صلاحية الجلسة.',
        ReturnFailureType.notFound => 'المرتجع غير موجود.',
        ReturnFailureType.saleNotConfirmed => 'الفاتورة الأصلية غير مؤكدة.',
        ReturnFailureType.emptyReturn => 'المرتجع بدون بنود.',
        ReturnFailureType.excessiveQuantity => 'الكمية تتجاوز المتاح.',
        ReturnFailureType.creditNoteRequiresCustomer => 'استرداد الرصيد يتطلب عميلاً.',
        ReturnFailureType.invalidStatusTransition => 'لا يمكن التعديل في الحالة الحالية.',
        ReturnFailureType.immutableConfirmedReturn => 'المرتجع المؤكد غير قابل للتعديل.',
        ReturnFailureType.referenceNotFound => 'أحد المراجع غير موجود.',
        ReturnFailureType.invalidResponse => 'تعذّر قراءة البيانات.',
        ReturnFailureType.unknown => 'تعذّر إتمام العملية.',
      };
}

class _ReturnLineTile extends StatefulWidget {
  const _ReturnLineTile({
    required this.line,
    required this.unitName,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onRemove,
  });

  final _ReturnCartLine line;
  final String unitName;
  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<double> onPriceChanged;
  final VoidCallback onRemove;

  @override
  State<_ReturnLineTile> createState() => _ReturnLineTileState();
}

class _ReturnLineTileState extends State<_ReturnLineTile> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: _fmt(widget.line.quantity));
    _priceCtrl = TextEditingController(text: _fmt(widget.line.unitPrice));
  }

  @override
  void didUpdateWidget(covariant _ReturnLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.quantity != widget.line.quantity && _qtyCtrl.text != _fmt(widget.line.quantity)) {
      _qtyCtrl.text = _fmt(widget.line.quantity);
    }
    if (oldWidget.line.unitPrice != widget.line.unitPrice && _priceCtrl.text != _fmt(widget.line.unitPrice)) {
      _priceCtrl.text = _fmt(widget.line.unitPrice);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final _ReturnCartLine line = widget.line;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(line.product.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: Icon(Icons.close, size: 18, color: scheme.error),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(isDense: true, labelText: 'الكمية', contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10), border: OutlineInputBorder()),
                  onChanged: (String v) {
                    final double d = double.tryParse(v) ?? 0;
                    if (d > 0) widget.onQuantityChanged(d);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Text(widget.unitName, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(isDense: true, labelText: 'السعر', contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10), border: OutlineInputBorder()),
                  onChanged: (String v) {
                    final double d = double.tryParse(v) ?? 0;
                    if (d >= 0) widget.onPriceChanged(d);
                  },
                ),
              ),
              const Spacer(),
              Text(AppFormatters.money(line.lineTotal), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}
