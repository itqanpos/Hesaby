// lib/features/purchases/presentation/pages/purchase_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
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

/// Purchase form page — creates or edits a draft purchase.
///
/// Pass [purchaseId] to edit an existing draft, or leave it `null` to create
/// a new purchase. Confirming from this page is a two-step action: save the
/// draft, then trigger the confirm. This keeps the form always handling a
/// real persisted purchase, avoiding partial states.
class PurchaseFormPage extends ConsumerStatefulWidget {
  const PurchaseFormPage({super.key, this.purchaseId});

  /// When non-null, the page loads and edits the given draft purchase.
  final String? purchaseId;

  @override
  ConsumerState<PurchaseFormPage> createState() =>
      _PurchaseFormPageState();
}

class _PurchaseFormPageState extends ConsumerState<PurchaseFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _invoiceNumberController =
      TextEditingController();
  final TextEditingController _discountController =
      TextEditingController(text: '0');
  final TextEditingController _taxController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();

  DateTime _purchaseDate = DateTime.now();
  String? _supplierId;
  final List<_DraftItem> _items = <_DraftItem>[];

  bool _isLoadingExisting = false;
  bool _isSubmitting = false;
  PurchaseFailureType? _failureType;

  bool get _isEditMode => widget.purchaseId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _isLoadingExisting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadExisting();
      });
    } else {
      _addEmptyItem();
    }
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _discountController.dispose();
    _taxController.dispose();
    _notesController.dispose();
    for (final _DraftItem item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Initial load (edit mode)
  // ---------------------------------------------------------------------------

  Future<void> _loadExisting() async {
    final String? purchaseId = widget.purchaseId;
    if (purchaseId == null) {
      return;
    }
    try {
      final Purchase purchase =
          await ref.read(purchaseRepositoryProvider).getPurchase(purchaseId);
      final List<PurchaseItem> items = await ref
          .read(purchaseRepositoryProvider)
          .listPurchaseItems(purchaseId);
      if (!mounted) {
        return;
      }
      setState(() {
        _purchaseDate = purchase.purchaseDate.toLocal();
        _supplierId = purchase.supplierId;
        _invoiceNumberController.text = purchase.invoiceNumber ?? '';
        _discountController.text = purchase.discount.toString();
        _taxController.text = purchase.taxAmount.toString();
        _notesController.text = purchase.notes ?? '';
        for (final _DraftItem item in _items) {
          item.dispose();
        }
        _items
          ..clear()
          ..addAll(items.map(_DraftItem.fromEntity));
        if (_items.isEmpty) {
          _addEmptyItem();
        }
        _isLoadingExisting = false;
      });
    } on PurchaseException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingExisting = false;
        _failureType = error.type;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingExisting = false;
        _failureType = PurchaseFailureType.unknown;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Items management
  // ---------------------------------------------------------------------------

  void _addEmptyItem() {
    setState(() {
      _items.add(_DraftItem.empty());
    });
  }

  void _removeItem(int index) {
    setState(() {
      final _DraftItem removed = _items.removeAt(index);
      removed.dispose();
      if (_items.isEmpty) {
        _items.add(_DraftItem.empty());
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Totals
  // ---------------------------------------------------------------------------

  double get _subtotal => _items.fold<double>(
        0,
        (double sum, _DraftItem item) => sum + item.lineTotal,
      );

  double get _discount => double.tryParse(_discountController.text.trim()) ?? 0;

  double get _taxAmount => double.tryParse(_taxController.text.trim()) ?? 0;

  double get _total => _subtotal - _discount + _taxAmount;

  // ---------------------------------------------------------------------------
  // Submission
  // ---------------------------------------------------------------------------

  /// Validates the form and returns the list of draft items, or `null` on
  /// validation failure. Empty rows are ignored (a row is considered empty
  /// when no product is selected).
  List<PurchaseItemDraft>? _collectItems() {
    final List<PurchaseItemDraft> result = <PurchaseItemDraft>[];
    for (final _DraftItem item in _items) {
      if (item.productId == null) {
        // Skip completely empty rows.
        continue;
      }
      if (item.unitId == null ||
          item.quantity <= 0 ||
          item.unitCost < 0) {
        setState(() => _failureType = PurchaseFailureType.invalidResponse);
        return null;
      }
      result.add(
        PurchaseItemDraft(
          productId: item.productId!,
          unitId: item.unitId!,
          quantity: item.quantity,
          unitCost: item.unitCost,
          notes: item.notes,
        ),
      );
    }
    return result;
  }

  Future<void> _submit({required bool andConfirm}) async {
    FocusScope.of(context).unfocus();

    if (_failureType != null) {
      setState(() => _failureType = null);
    }

    final bool isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final String? supplierId = _supplierId;
    if (supplierId == null || supplierId.isEmpty) {
      setState(() => _failureType = PurchaseFailureType.supplierNotFound);
      return;
    }

    final CompanyContextState contextState =
        ref.read(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;
    if (branchId == null) {
      setState(() => _failureType = PurchaseFailureType.branchNotFound);
      return;
    }

    final List<PurchaseItemDraft>? items = _collectItems();
    if (items == null) {
      return;
    }

    if (andConfirm && items.isEmpty) {
      setState(() => _failureType = PurchaseFailureType.emptyPurchase);
      return;
    }

    setState(() => _isSubmitting = true);

    final PurchasesNotifier notifier =
        ref.read(purchasesProvider.notifier);
    final String invoiceNumber = _invoiceNumberController.text.trim();
    final String notes = _notesController.text.trim();

    try {
      Purchase saved;
      if (_isEditMode) {
        saved = await notifier.updateDraft(
          purchaseId: widget.purchaseId!,
          branchId: branchId,
          supplierId: supplierId,
          purchaseDate: _purchaseDate,
          items: items,
          invoiceNumber: invoiceNumber.isEmpty ? null : invoiceNumber,
          discount: _discount,
          taxAmount: _taxAmount,
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        saved = await notifier.createPurchase(
          branchId: branchId,
          supplierId: supplierId,
          purchaseDate: _purchaseDate,
          items: items,
          invoiceNumber: invoiceNumber.isEmpty ? null : invoiceNumber,
          discount: _discount,
          taxAmount: _taxAmount,
          notes: notes.isEmpty ? null : notes,
        );
      }

      if (andConfirm) {
        await notifier.confirmPurchase(saved.id);
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on PurchaseException catch (error) {
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
        _failureType = PurchaseFailureType.unknown;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoadingExisting) {
      return AppShell(
        appBar: AppBar(title: const Text('تعديل فاتورة')),
        body: const AppLoader(),
      );
    }

    final AsyncValue<List<Supplier>> suppliersAsync =
        ref.watch(suppliersProvider);
    final AsyncValue<List<Product>> productsAsync =
        ref.watch(productsProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    final bool anyLoading = suppliersAsync.isLoading ||
        productsAsync.isLoading ||
        unitsAsync.isLoading;
    final Object? firstError =
        suppliersAsync.error ?? productsAsync.error ?? unitsAsync.error;

    return AppShell(
      appBar: AppBar(
        title: Text(_isEditMode ? 'تعديل فاتورة' : 'فاتورة جديدة'),
      ),
      body: Builder(
        builder: (BuildContext context) {
          if (anyLoading) {
            return const AppLoader();
          }
          if (firstError != null) {
            return AppErrorView(
              title: 'تعذّر تحميل البيانات',
              message: _errorMessage(firstError),
              retryLabel: 'إعادة المحاولة',
              onRetry: () {
                ref.invalidate(suppliersProvider);
                ref.invalidate(productsProvider);
                ref.invalidate(unitsProvider);
              },
            );
          }

          final List<Supplier> suppliers =
              suppliersAsync.value ?? const <Supplier>[];
          final List<Product> products =
              productsAsync.value ?? const <Product>[];
          final List<Unit> units = unitsAsync.value ?? const <Unit>[];

          return Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildHeaderSection(suppliers: suppliers),
                  const SizedBox(height: 16),
                  _buildItemsSection(products: products, units: units),
                  const SizedBox(height: 16),
                  _buildTotalsSection(),
                  const SizedBox(height: 16),
                  _buildNotesSection(),
                  if (_failureType != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _FailureBanner(message: _failureMessage(_failureType!)),
                  ],
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderSection({required List<Supplier> suppliers}) {
    final ThemeData theme = Theme.of(context);
    final DateFormat dateFormat = DateFormat.yMd('ar_EG');

    final Set<String> knownIds = <String>{
      for (final Supplier supplier in suppliers) supplier.id,
    };
    final String? currentSupplier =
        (_supplierId != null && knownIds.contains(_supplierId))
            ? _supplierId
            : null;

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
            Text('بيانات الفاتورة', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: currentSupplier,
              isExpanded: true,
              hint: const Text('اختر المورد'),
              decoration: const InputDecoration(
                labelText: 'المورد',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final Supplier supplier in suppliers)
                  DropdownMenuItem<String>(
                    value: supplier.id,
                    child: Text(supplier.name),
                  ),
              ],
              onChanged: _isSubmitting
                  ? null
                  : (String? value) {
                      setState(() => _supplierId = value);
                    },
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return 'الرجاء اختيار المورد';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _isSubmitting
                  ? null
                  : () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _purchaseDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _purchaseDate = picked);
                      }
                    },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'تاريخ الفاتورة',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(dateFormat.format(_purchaseDate)),
                    const Icon(Icons.calendar_today_outlined, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _invoiceNumberController,
              label: 'رقم الفاتورة — اختياري',
              hint: 'مثال: INV-2026-001',
              enabled: !_isSubmitting,
              validator: (String? value) {
                final String trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return null;
                }
                if (trimmed.length > 64) {
                  return 'رقم الفاتورة طويل جدًا';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsSection({
    required List<Product> products,
    required List<Unit> units,
  }) {
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'بنود الفاتورة',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                AppButton(
                  label: 'إضافة بند',
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.small,
                  onPressed: _isSubmitting ? null : _addEmptyItem,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _items.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == _items.length - 1 ? 0 : 12,
                ),
                child: _ItemRow(
                  item: _items[i],
                  products: products,
                  units: units,
                  enabled: !_isSubmitting,
                  onChanged: () => setState(() {}),
                  onRemove:
                      _items.length > 1 ? () => _removeItem(i) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection() {
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
            Row(
              children: <Widget>[
                Expanded(
                  child: AppTextField(
                    controller: _discountController,
                    label: 'الخصم',
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (String _) => setState(() {}),
                    validator: _validateNonNegative,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    controller: _taxController,
                    label: 'الضريبة',
                    enabled: !_isSubmitting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (String _) => setState(() {}),
                    validator: _validateNonNegative,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _totalLine('المجموع الفرعي', moneyFormat.format(_subtotal)),
            const SizedBox(height: 4),
            _totalLine('الخصم', moneyFormat.format(_discount)),
            const SizedBox(height: 4),
            _totalLine('الضريبة', moneyFormat.format(_taxAmount)),
            const Divider(height: 20),
            _totalLine(
              'الإجمالي',
              moneyFormat.format(_total),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalLine(String label, String value, {bool emphasized = false}) {
    final ThemeData theme = Theme.of(context);
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

  Widget _buildNotesSection() {
    return AppTextField(
      controller: _notesController,
      label: 'ملاحظات — اختياري',
      enabled: !_isSubmitting,
      maxLines: 3,
      validator: (String? value) {
        final String trimmed = value?.trim() ?? '';
        if (trimmed.length > 2000) {
          return 'الملاحظات طويلة جدًا (الحد الأقصى 2000 حرف)';
        }
        return null;
      },
    );
  }

  Widget _buildActions() {
    return Row(
      children: <Widget>[
        Expanded(
          child: AppButton(
            label: 'حفظ كمسودة',
            variant: AppButtonVariant.secondary,
            isLoading: _isSubmitting,
            onPressed: _isSubmitting
                ? null
                : () => _submit(andConfirm: false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppButton(
            label: 'حفظ وتأكيد',
            isLoading: _isSubmitting,
            onPressed: _isSubmitting
                ? null
                : () => _submit(andConfirm: true),
          ),
        ),
      ],
    );
  }

  String? _validateNonNegative(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final double? parsed = double.tryParse(trimmed);
    if (parsed == null) {
      return 'الرجاء إدخال رقم صحيح';
    }
    if (parsed < 0) {
      return 'لا يمكن أن تكون القيمة سالبة';
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// Draft item row
// -----------------------------------------------------------------------------

/// Mutable editing state for one purchase line.
class _DraftItem {
  _DraftItem({
    this.productId,
    this.unitId,
    required this.quantityController,
    required this.unitCostController,
    this.notes,
  });

  factory _DraftItem.empty() => _DraftItem(
        quantityController: TextEditingController(text: '1'),
        unitCostController: TextEditingController(text: '0'),
      );

  factory _DraftItem.fromEntity(PurchaseItem entity) => _DraftItem(
        productId: entity.productId,
        unitId: entity.unitId,
        quantityController: TextEditingController(
          text: _formatNumber(entity.quantity),
        ),
        unitCostController: TextEditingController(
          text: _formatNumber(entity.unitCost),
        ),
        notes: entity.notes,
      );

  String? productId;
  String? unitId;
  final TextEditingController quantityController;
  final TextEditingController unitCostController;
  String? notes;

  double get quantity =>
      double.tryParse(quantityController.text.trim()) ?? 0;

  double get unitCost =>
      double.tryParse(unitCostController.text.trim()) ?? 0;

  double get lineTotal => quantity * unitCost;

  void dispose() {
    quantityController.dispose();
    unitCostController.dispose();
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.products,
    required this.units,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftItem item;
  final List<Product> products;
  final List<Unit> units;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NumberFormat moneyFormat = NumberFormat.currency(
      locale: 'ar_EG',
      symbol: 'ج.م ',
      decimalDigits: 2,
    );

    final Set<String> productIds = <String>{
      for (final Product product in products) product.id,
    };
    final String? currentProduct =
        (item.productId != null && productIds.contains(item.productId))
            ? item.productId
            : null;

    // Units filtered to the product's default unit and its extra units when
    // a product is selected; otherwise all units.
    final List<Unit> availableUnits = _unitsForProduct(item.productId);

    final Set<String> availableUnitIds = <String>{
      for (final Unit unit in availableUnits) unit.id,
    };
    final String? currentUnit =
        (item.unitId != null && availableUnitIds.contains(item.unitId))
            ? item.unitId
            : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: currentProduct,
                    isExpanded: true,
                    hint: const Text('اختر منتجًا'),
                    decoration: const InputDecoration(
                      labelText: 'المنتج',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final Product product in products)
                        DropdownMenuItem<String>(
                          value: product.id,
                          child: Text(product.name),
                        ),
                    ],
                    onChanged: enabled
                        ? (String? value) {
                            item.productId = value;
                            // Reset unit when product changes.
                            item.unitId = null;
                            onChanged();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'حذف البند',
                    onPressed: enabled ? onRemove : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: currentUnit,
                    isExpanded: true,
                    hint: const Text('الوحدة'),
                    decoration: const InputDecoration(
                      labelText: 'الوحدة',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final Unit unit in availableUnits)
                        DropdownMenuItem<String>(
                          value: unit.id,
                          child: Text(unit.name),
                        ),
                    ],
                    onChanged: enabled
                        ? (String? value) {
                            item.unitId = value;
                            onChanged();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: AppTextField(
                    controller: item.quantityController,
                    label: 'الكمية',
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (String _) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: AppTextField(
                    controller: item.unitCostController,
                    label: 'تكلفة الوحدة',
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (String _) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                'الإجمالي: ${moneyFormat.format(item.lineTotal)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the list of units eligible for the given product.
  ///
  /// When no product is selected, all units are returned. When a product is
  /// selected, the returned list starts with its default unit and (in a
  /// later phase) will include its product_units conversions. For Phase 7
  /// we surface the default unit plus any other unit, because the line
  /// simply needs a valid unit of the same company — the composite foreign
  /// key guarantees tenant safety.
  List<Unit> _unitsForProduct(String? productId) {
    if (productId == null) {
      return units;
    }
    final Product? product = products
        .where((Product p) => p.id == productId)
        .cast<Product?>()
        .firstWhere((Product? p) => true, orElse: () => null);
    if (product == null) {
      return units;
    }
    final Unit? defaultUnit = units
        .where((Unit u) => u.id == product.defaultUnitId)
        .cast<Unit?>()
        .firstWhere((Unit? u) => true, orElse: () => null);

    // Return the default unit first, then the remaining units. The list is
    // de-duplicated by id.
    final List<Unit> ordered = <Unit>[];
    final Set<String> seen = <String>{};
    if (defaultUnit != null) {
      ordered.add(defaultUnit);
      seen.add(defaultUnit.id);
    }
    for (final Unit unit in units) {
      if (seen.add(unit.id)) {
        ordered.add(unit);
      }
    }
    return ordered;
  }
}

// -----------------------------------------------------------------------------
// Failure banner
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
        'الفاتورة المطلوبة غير موجودة.',
      PurchaseFailureType.invalidStatusTransition =>
        'لا يمكن إجراء هذه العملية على الفاتورة في حالتها الحالية.',
      PurchaseFailureType.emptyPurchase =>
        'لا يمكن تأكيد فاتورة بدون بنود. أضف منتجًا واحدًا على الأقل.',
      PurchaseFailureType.invoiceNumberConflict =>
        'يوجد فاتورة أخرى بنفس الرقم في هذه الشركة.',
      PurchaseFailureType.supplierNotFound =>
        'المورد المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.branchNotFound =>
        'الفرع المختار غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.productNotFound =>
        'أحد المنتجات المختارة غير متاح. يرجى إعادة اختياره.',
      PurchaseFailureType.unitNotFound =>
        'إحدى الوحدات المختارة غير متاحة. يرجى إعادة اختيارها.',
      PurchaseFailureType.insufficientStock =>
        'لا يمكن إتمام العملية؛ الرصيد غير كافٍ.',
      PurchaseFailureType.invalidResponse =>
        'القيم المُدخلة غير صحيحة. يرجى التحقق من الكميات والأسعار.',
      PurchaseFailureType.unknown =>
        'تعذّر حفظ الفاتورة. يرجى المحاولة مرة أخرى.',
    };
