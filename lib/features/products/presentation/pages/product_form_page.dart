// lib/features/products/presentation/pages/product_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../pos/domain/services/barcode_scanner_service.dart';
import '../../../pos/presentation/services/mobile_scanner_service.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/unit.dart';
import '../../domain/repositories/product_repository.dart';
import '../providers/category_providers.dart';
import '../providers/product_providers.dart';
import '../providers/unit_providers.dart';

/// Opens the product create / edit **page** (full-screen, not a dialog).
Future<bool?> showProductFormDialog({
  required BuildContext context,
  Product? existing,
  String? initialBarcode,
  ValueChanged<Product>? onSaved,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (BuildContext _) => ProductFormPage(
        existing: existing,
        initialBarcode: initialBarcode,
        onSaved: onSaved,
      ),
    ),
  );
}

/// Full-page create / edit form for a product.
class ProductFormPage extends ConsumerStatefulWidget {
  const ProductFormPage({
    super.key,
    this.existing,
    this.initialBarcode,
    this.onSaved,
  });

  final Product? existing;
  final String? initialBarcode;
  final ValueChanged<Product>? onSaved;

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  /// Reuses the same scanner that powers POS — already tuned for speed
  /// (`scanWindow`, `autoZoom`, `unrestricted` detection).
  static const BarcodeScannerService _scanner = MobileScannerServiceImpl();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _minSellingPriceController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _descriptionController;

  String? _categoryId;
  String? _defaultUnitId;
  bool _isActive = true;

  bool _isSubmitting = false;
  bool _showOptional = false;
  bool _anySaved = false;
  ProductFailureType? _failureType;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Product? existing = widget.existing;

    _nameController = TextEditingController(text: existing?.name ?? '');
    _skuController = TextEditingController(text: existing?.sku ?? '');
    _barcodeController = TextEditingController(
      text: existing?.barcode ?? widget.initialBarcode ?? '',
    );
    _sellingPriceController = TextEditingController(
      text: existing == null ? '' : _formatNumber(existing.sellingPrice),
    );
    _costPriceController = TextEditingController(
      text: existing == null ? '' : _formatNumber(existing.costPrice),
    );
    _minSellingPriceController = TextEditingController(
      text: existing?.minSellingPrice == null
          ? ''
          : _formatNumber(existing!.minSellingPrice!),
    );
    _taxRateController = TextEditingController(
      text: existing?.taxRate == null
          ? ''
          : _formatNumber(existing!.taxRate!),
    );
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );

    _categoryId = existing?.categoryId;
    _defaultUnitId = existing?.defaultUnitId;
    _isActive = existing?.isActive ?? true;
    _showOptional = (existing?.description ?? '').isNotEmpty;

    _sellingPriceController.addListener(_onPriceChanged);
    _costPriceController.addListener(_onPriceChanged);
  }

  @override
  void dispose() {
    _sellingPriceController.removeListener(_onPriceChanged);
    _costPriceController.removeListener(_onPriceChanged);
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _minSellingPriceController.dispose();
    _taxRateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onPriceChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String? _emptyToNull(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _parseDouble(String value) => double.tryParse(value.trim());

  // ---------------------------------------------------------------------------
  // Margin computation
  // ---------------------------------------------------------------------------

  ({double profit, double? marginPercent})? _computeMargin() {
    final double? selling = _parseDouble(_sellingPriceController.text);
    final double? cost = _parseDouble(_costPriceController.text);
    if (selling == null || cost == null) return null;
    if (selling < 0 || cost < 0) return null;

    final double profit = selling - cost;
    final double? percent = cost > 0 ? (profit / cost) * 100 : null;
    return (profit: profit, marginPercent: percent);
  }

  // ---------------------------------------------------------------------------
  // Barcode scanner
  // ---------------------------------------------------------------------------

  /// Opens the tuned barcode scanner and writes the result into the
  /// barcode field.
  ///
  /// Uses the same service as the POS so the scanning experience is
  /// identical across the app.
  Future<void> _openBarcodeScanner() async {
    FocusScope.of(context).unfocus();

    if (!_scanner.isSupported) {
      _showScannerUnsupportedMessage();
      return;
    }

    final String? scanned = await _scanner.scan(context);
    if (!mounted) return;
    if (scanned == null || scanned.trim().isEmpty) return;

    final String value = scanned.trim();
    _barcodeController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('تم مسح الباركود: $value'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showScannerUnsupportedMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'المسح بالكاميرا غير مدعوم على هذا الجهاز. '
            'استخدم قارئ باركود خارجي أو اكتب الرقم يدويًا.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Toggle active
  // ---------------------------------------------------------------------------

  void _toggleActive() {
    setState(() => _isActive = !_isActive);
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_failureType != null) {
      setState(() => _failureType = null);
    }

    final bool isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final String? unitId = _defaultUnitId;
    if (unitId == null || unitId.isEmpty) {
      setState(() => _failureType = ProductFailureType.unitNotFound);
      return;
    }

    final double? sellingPrice = _parseDouble(_sellingPriceController.text);
    final double? costPrice = _parseDouble(_costPriceController.text);
    if (sellingPrice == null || costPrice == null) {
      setState(() => _failureType = ProductFailureType.invalidResponse);
      return;
    }

    final double? minSellingPrice =
        _emptyToNull(_minSellingPriceController.text) == null
            ? null
            : _parseDouble(_minSellingPriceController.text);
    final double? taxRate = _emptyToNull(_taxRateController.text) == null
        ? null
        : _parseDouble(_taxRateController.text);

    setState(() => _isSubmitting = true);

    final ProductsNotifier notifier = ref.read(productsProvider.notifier);
    final String name = _nameController.text.trim();
    final String? sku = _emptyToNull(_skuController.text);
    final String? barcode = _emptyToNull(_barcodeController.text);
    final String? description = _emptyToNull(_descriptionController.text);

    try {
      final Product saved;
      if (widget.existing == null) {
        saved = await notifier.createProduct(
          name: name,
          defaultUnitId: unitId,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          categoryId: _categoryId,
          sku: sku,
          barcode: barcode,
          description: description,
          minSellingPrice: minSellingPrice,
          taxRate: taxRate,
        );
      } else {
        saved = await notifier.updateProduct(
          productId: widget.existing!.id,
          name: name,
          defaultUnitId: unitId,
          categoryId: _categoryId,
          clearCategory: _categoryId == null,
          sku: sku,
          clearSku: sku == null,
          barcode: barcode,
          clearBarcode: barcode == null,
          description: description,
          clearDescription: description == null,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          minSellingPrice: minSellingPrice,
          clearMinSellingPrice: minSellingPrice == null,
          taxRate: taxRate,
          clearTaxRate: taxRate == null,
          isActive: _isActive,
        );
      }

      widget.onSaved?.call(saved);
      _anySaved = true;

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ProductException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failureType = error.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failureType = ProductFailureType.unknown;
      });
    }
  }

  void _handleClose() {
    Navigator.of(context).pop(_anySaved);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final AsyncValue<List<ProductCategory>> categoriesAsync =
        ref.watch(categoriesProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);
    final ProductFailureType? failure = _failureType;

    return AppShell(
      includeNavigation: false,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'رجوع',
          icon: const Icon(Icons.arrow_back),
          onPressed: _isSubmitting ? null : _handleClose,
        ),
        title: Text(_isEditing ? 'تعديل منتج' : 'إضافة منتج'),
        actions: <Widget>[
          IconButton(
            tooltip: 'حفظ',
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: _isSubmitting ? null : _submit,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: <Widget>[
            const _SectionHeader(
              title: 'المعلومات الأساسية',
              icon: Icons.info_outline,
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _nameController,
              label: 'اسم المنتج *',
              hint: 'مثال: بيبسي 1 لتر',
              enabled: !_isSubmitting,
              autofocus: !_isEditing,
              textInputAction: TextInputAction.next,
              validator: (String? value) =>
                  _validateRequired(value, 'اسم المنتج'),
            ),
            const SizedBox(height: 12),
            _ResponsiveRow(
              left: categoriesAsync.when(
                data: _buildCategoryField,
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
                error: (Object _, StackTrace __) =>
                    _buildLookupError('الفئات'),
              ),
              right: unitsAsync.when(
                data: _buildUnitField,
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
                error: (Object _, StackTrace __) =>
                    _buildLookupError('الوحدات'),
              ),
            ),

            const SizedBox(height: 20),

            const _SectionHeader(
              title: 'الأسعار',
              icon: Icons.attach_money_outlined,
            ),
            const SizedBox(height: 10),
            _ResponsiveRow(
              left: AppTextField(
                controller: _costPriceController,
                label: 'سعر التكلفة *',
                hint: '0.00',
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                validator: _validatePrice,
              ),
              right: AppTextField(
                controller: _sellingPriceController,
                label: 'سعر البيع *',
                hint: '0.00',
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                validator: _validatePrice,
              ),
            ),
            const SizedBox(height: 10),
            _MarginIndicator(margin: _computeMargin()),
            const SizedBox(height: 12),
            _ResponsiveRow(
              left: AppTextField(
                controller: _minSellingPriceController,
                label: 'الحد الأدنى للبيع',
                hint: 'اختياري — للتفاوض',
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                validator: _validateOptionalPrice,
              ),
              right: AppTextField(
                controller: _taxRateController,
                label: 'الضريبة %',
                hint: '0-100',
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                validator: _validateTaxRate,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'الحد الأدنى: أقل سعر يمكن للكاشير إدخاله. '
              'الضريبة: تُطبَّق على هذا المنتج تحديدًا.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 20),

            const _SectionHeader(
              title: 'التعريف',
              icon: Icons.qr_code_2_outlined,
            ),
            const SizedBox(height: 10),
            _ResponsiveRow(
              left: AppTextField(
                controller: _skuController,
                label: 'رمز المنتج (SKU)',
                hint: 'اختياري',
                enabled: !_isSubmitting,
                textInputAction: TextInputAction.next,
                validator: _validateSku,
              ),
              right: AppTextField(
                controller: _barcodeController,
                label: 'الباركود',
                hint: 'اختياري — أو امسح ضوئيًا',
                enabled: !_isSubmitting,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                validator: _validateBarcode,
                suffixIcon: IconButton(
                  tooltip: 'مسح الباركود بالكاميرا',
                  icon: Icon(
                    Icons.qr_code_scanner,
                    color: scheme.primary,
                  ),
                  onPressed: _isSubmitting ? null : _openBarcodeScanner,
                ),
              ),
            ),

            const SizedBox(height: 20),

            _CollapsibleHeader(
              title: 'تفاصيل إضافية',
              icon: Icons.notes_outlined,
              isExpanded: _showOptional,
              onToggle: () =>
                  setState(() => _showOptional = !_showOptional),
              badge: _descriptionController.text.isNotEmpty ? '•' : null,
            ),
            if (_showOptional) ...<Widget>[
              const SizedBox(height: 10),
              AppTextField(
                controller: _descriptionController,
                label: 'الوصف',
                hint: 'وصف تفصيلي (اختياري)',
                enabled: !_isSubmitting,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                validator: _validateDescription,
              ),
            ],

            const SizedBox(height: 20),

            _StatusSection(
              isActive: _isActive,
              enabled: !_isSubmitting,
              onToggle: _toggleActive,
            ),

            if (failure != null) ...<Widget>[
              const SizedBox(height: 16),
              _FailureBanner(message: _failureMessage(failure)),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Field builders
  // ---------------------------------------------------------------------------

  Widget _buildCategoryField(List<ProductCategory> categories) {
    final Set<String> knownIds = <String>{
      for (final ProductCategory category in categories) category.id,
    };
    final String? currentId = _categoryId;
    final bool hasCurrent = currentId != null && knownIds.contains(currentId);

    return DropdownButtonFormField<String?>(
      initialValue: hasCurrent ? currentId : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'الفئة',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('بدون فئة'),
        ),
        for (final ProductCategory category in categories)
          DropdownMenuItem<String?>(
            value: category.id,
            child: Text(category.name),
          ),
      ],
      onChanged: _isSubmitting
          ? null
          : (String? value) {
              setState(() => _categoryId = value);
            },
    );
  }

  Widget _buildUnitField(List<Unit> units) {
    final Set<String> knownIds = <String>{
      for (final Unit unit in units) unit.id,
    };
    final String? currentId = _defaultUnitId;
    final bool hasCurrent = currentId != null && knownIds.contains(currentId);

    return DropdownButtonFormField<String>(
      initialValue: hasCurrent ? currentId : null,
      isExpanded: true,
      hint: const Text('اختر الوحدة'),
      decoration: const InputDecoration(
        labelText: 'الوحدة الأساسية *',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
      items: <DropdownMenuItem<String>>[
        for (final Unit unit in units)
          DropdownMenuItem<String>(
            value: unit.id,
            child: Text(unit.name),
          ),
      ],
      onChanged: _isSubmitting
          ? null
          : (String? value) {
              setState(() => _defaultUnitId = value);
            },
      validator: (String? value) {
        if (value == null || value.isEmpty) {
          return 'الرجاء اختيار الوحدة';
        }
        return null;
      },
    );
  }

  Widget _buildLookupError(String label) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: scheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('تعذّر تحميل $label')),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Validators
  // ---------------------------------------------------------------------------

  String? _validateRequired(String? value, String fieldName) {
    final ValidationError? error = Validators.required(value);
    return error == null ? null : 'الرجاء إدخال $fieldName';
  }

  String? _validateSku(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 64) {
      return 'الرمز طويل جدًا (الحد الأقصى 64 حرفًا)';
    }
    return null;
  }

  String? _validateBarcode(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 64) {
      return 'الباركود طويل جدًا (الحد الأقصى 64 حرفًا)';
    }
    return null;
  }

  String? _validateDescription(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 2000) {
      return 'الوصف طويل جدًا (الحد الأقصى 2000 حرف)';
    }
    return null;
  }

  String? _validatePrice(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'الرجاء إدخال السعر';
    }
    final double? parsed = double.tryParse(trimmed);
    if (parsed == null) {
      return 'الرجاء إدخال رقم صحيح';
    }
    if (parsed < 0) {
      return 'لا يمكن أن يكون السعر سالبًا';
    }
    return null;
  }

  String? _validateOptionalPrice(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final double? parsed = double.tryParse(trimmed);
    if (parsed == null) {
      return 'الرجاء إدخال رقم صحيح';
    }
    if (parsed < 0) {
      return 'لا يمكن أن يكون السعر سالبًا';
    }
    final double? selling = _parseDouble(_sellingPriceController.text);
    if (selling != null && parsed > selling) {
      return 'الحد الأدنى لا يمكن أن يتجاوز سعر البيع';
    }
    return null;
  }

  String? _validateTaxRate(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final double? parsed = double.tryParse(trimmed);
    if (parsed == null) {
      return 'الرجاء إدخال رقم صحيح';
    }
    if (parsed < 0 || parsed > 100) {
      return 'النسبة يجب أن تكون بين 0 و 100';
    }
    return null;
  }
}

// ============================================================================
// Section header
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: scheme.outlineVariant),
        ),
      ],
    );
  }
}

// ============================================================================
// Collapsible header
// ============================================================================

class _CollapsibleHeader extends StatelessWidget {
  const _CollapsibleHeader({
    required this.title,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    this.badge,
  });

  final String title;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (badge != null) ...<Widget>[
                const SizedBox(width: 6),
                Text(badge!, style: TextStyle(color: scheme.primary)),
              ],
              const Spacer(),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Responsive row
// ============================================================================

class _ResponsiveRow extends StatelessWidget {
  const _ResponsiveRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              left,
              const SizedBox(height: 12),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Margin indicator
// ============================================================================

class _MarginIndicator extends StatelessWidget {
  const _MarginIndicator({required this.margin});

  final ({double profit, double? marginPercent})? margin;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (margin == null) {
      return Container(
        height: 44,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            'أدخل التكلفة وسعر البيع لحساب الربح',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final double profit = margin!.profit;
    final double? percent = margin!.marginPercent;
    final bool isProfit = profit >= 0;

    final Color color =
        isProfit ? const Color(0xFF0F7B6C) : scheme.error;

    final String sign = isProfit ? '+' : '';
    final String profitLabel =
        '$sign${AppFormatters.moneyPlain(profit)} ج.م';
    final String percentLabel =
        percent == null ? '—' : '$sign${percent.toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isProfit ? Icons.trending_up : Icons.trending_down,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'الربح المتوقع',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                profitLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (percent != null)
                Text(
                  'هامش: $percentLabel',
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Status section — تعطيل / تفعيل
// ============================================================================

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.isActive,
    required this.enabled,
    required this.onToggle,
  });

  final bool isActive;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color tone =
        isActive ? const Color(0xFF0F7B6C) : const Color(0xFFB26A00);
    final IconData statusIcon =
        isActive ? Icons.check_circle_outline : Icons.pause_circle_outline;
    final String title = isActive ? 'المنتج نشط' : 'المنتج معطّل';
    final String description = isActive
        ? 'يظهر للكاشير في نقطة البيع والقوائم.'
        : 'لن يظهر للكاشير عند البيع حتى تفعّله مجددًا.';

    final String actionLabel =
        isActive ? 'تعطيل المنتج' : 'تفعيل المنتج';
    final IconData actionIcon = isActive
        ? Icons.visibility_off_outlined
        : Icons.visibility_outlined;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(statusIcon, color: tone, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tone,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: enabled ? onToggle : null,
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
              style: TextButton.styleFrom(
                foregroundColor: tone,
                backgroundColor: tone.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Failure banner
// ============================================================================

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

// ============================================================================
// Localization helpers
// ============================================================================

String _failureMessage(ProductFailureType type) => switch (type) {
      ProductFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      ProductFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      ProductFailureType.notFound => 'المنتج غير موجود.',
      ProductFailureType.skuConflict =>
        'يوجد منتج آخر بنفس الـ SKU في هذه الشركة.',
      ProductFailureType.barcodeConflict =>
        'يوجد منتج آخر بنفس الباركود في هذه الشركة.',
      ProductFailureType.categoryNotFound =>
        'التصنيف المختار غير متاح. يرجى إعادة اختياره.',
      ProductFailureType.unitNotFound => 'الرجاء اختيار الوحدة الأساسية.',
      ProductFailureType.inUse => 'لا يمكن إتمام العملية لوجود سجلات مرتبطة.',
      ProductFailureType.invalidResponse => 'الرجاء إدخال أسعار صحيحة.',
      ProductFailureType.unknown =>
        'تعذّر حفظ المنتج. يرجى المحاولة مرة أخرى.',
    };
