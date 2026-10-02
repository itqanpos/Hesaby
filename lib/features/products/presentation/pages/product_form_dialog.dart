import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/unit.dart';
import '../providers/category_providers.dart';
import '../providers/product_providers.dart';
import '../providers/unit_providers.dart';

/// يعرض نافذة إضافة / تعديل منتج.
///
/// مرّر [existing] لتعديل منتج قائم، أو اتركه `null` لإضافة منتج جديد.
/// تُعيد `true` عند الحفظ بنجاح، و `false` عند الإلغاء، و `null` عند
/// إغلاق النافذة دون قرار.
Future<bool?> showProductFormDialog({
  required BuildContext context,
  Product? existing,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProductFormDialog(existing: existing),
  );
}

class _ProductFormDialog extends ConsumerStatefulWidget {
  const _ProductFormDialog({this.existing});

  final Product? existing;

  @override
  ConsumerState<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  static const String _noCategorySentinel = '__no_category__';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _minSellingPriceController;
  late final TextEditingController _taxRateController;
  late final TextEditingController _descriptionController;

  String? _categoryId;
  String? _defaultUnitId;
  bool _isActive = true;

  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final Product? product = widget.existing;

    _nameController = TextEditingController(text: product?.name ?? '');
    _skuController = TextEditingController(text: product?.sku ?? '');
    _barcodeController = TextEditingController(text: product?.barcode ?? '');
    _costPriceController = TextEditingController(
      text: product == null ? '' : _formatNumber(product.costPrice),
    );
    _sellingPriceController = TextEditingController(
      text: product == null ? '' : _formatNumber(product.sellingPrice),
    );

    final double? minSellingPrice = product?.minSellingPrice;
    _minSellingPriceController = TextEditingController(
      text: minSellingPrice == null ? '' : _formatNumber(minSellingPrice),
    );

    final double? taxRate = product?.taxRate;
    _taxRateController = TextEditingController(
      text: taxRate == null ? '' : _formatNumber(taxRate),
    );

    _descriptionController = TextEditingController(
      text: product?.description ?? '',
    );

    _categoryId = product?.categoryId;
    _defaultUnitId = product?.defaultUnitId;
    _isActive = product?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _minSellingPriceController.dispose();
    _taxRateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String? _emptyToNull(String raw) {
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _parseNullableNumber(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'الرجاء إدخال $label';
    }
    return null;
  }

  String? _validateNonNegativeNumber(
    String? value,
    String label, {
    bool required = true,
  }) {
    final String raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return required ? 'الرجاء إدخال $label' : null;
    }
    final double? parsed = double.tryParse(raw);
    if (parsed == null) {
      return 'الرجاء إدخال رقم صحيح';
    }
    if (parsed < 0) {
      return 'لا يمكن أن يكون $label سالباً';
    }
    return null;
  }

  Future<void> _submit() async {
    final FormState? formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    final String unitId = _defaultUnitId ?? '';
    if (unitId.isEmpty) {
      setState(() {
        _errorMessage = 'الرجاء اختيار الوحدة الأساسية';
      });
      return;
    }

    final double? costPrice =
        double.tryParse(_costPriceController.text.trim());
    final double? sellingPrice =
        double.tryParse(_sellingPriceController.text.trim());

    if (costPrice == null || sellingPrice == null) {
      setState(() {
        _errorMessage = 'الرجاء إدخال أسعار صحيحة';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final notifier = ref.read(productsProvider.notifier);

      final String name = _nameController.text.trim();
      final String? sku = _emptyToNull(_skuController.text);
      final String? barcode = _emptyToNull(_barcodeController.text);
      final String? description = _emptyToNull(_descriptionController.text);
      final double? minSellingPrice =
          _parseNullableNumber(_minSellingPriceController.text);
      final double? taxRate = _parseNullableNumber(_taxRateController.text);

      final Product? existing = widget.existing;

      if (existing == null) {
        await notifier.createProduct(
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
        await notifier.updateProduct(
          productId: existing.id,
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

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      AppLogger.error('فشل حفظ المنتج', error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = 'تعذّر حفظ المنتج، الرجاء المحاولة مرة أخرى';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ProductCategory>> categoriesAsync =
        ref.watch(categoriesProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);
    final String? errorMessage = _errorMessage;

    return AlertDialog(
      title: Text(_isEditing ? 'تعديل منتج' : 'إضافة منتج'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: _nameController,
                  label: 'اسم المنتج',
                  textInputAction: TextInputAction.next,
                  enabled: !_isSaving,
                  validator: (value) =>
                      _validateRequired(value, 'اسم المنتج'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _skuController,
                  label: 'رمز المنتج (SKU)',
                  textInputAction: TextInputAction.next,
                  enabled: !_isSaving,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _barcodeController,
                  label: 'الباركود',
                  textInputAction: TextInputAction.next,
                  enabled: !_isSaving,
                ),
                const SizedBox(height: 12),
                _buildCategoriesField(categoriesAsync),
                const SizedBox(height: 12),
                _buildUnitsField(unitsAsync),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _costPriceController,
                  label: 'سعر التكلفة',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_isSaving,
                  validator: (value) =>
                      _validateNonNegativeNumber(value, 'سعر التكلفة'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _sellingPriceController,
                  label: 'سعر البيع',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_isSaving,
                  validator: (value) =>
                      _validateNonNegativeNumber(value, 'سعر البيع'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _minSellingPriceController,
                  label: 'أدنى سعر للبيع (اختياري)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_isSaving,
                  validator: (value) => _validateNonNegativeNumber(
                    value,
                    'أدنى سعر للبيع',
                    required: false,
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _taxRateController,
                  label: 'نسبة الضريبة % (اختياري)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_isSaving,
                  validator: (value) => _validateNonNegativeNumber(
                    value,
                    'نسبة الضريبة',
                    required: false,
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _descriptionController,
                  label: 'الوصف (اختياري)',
                  maxLines: 3,
                  enabled: !_isSaving,
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('نشط'),
                    value: _isActive,
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            setState(() {
                              _isActive = value;
                            });
                          },
                  ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'إلغاء',
          variant: AppButtonVariant.text,
          onPressed: _isSaving
              ? null
              : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _isEditing ? 'حفظ التعديلات' : 'إضافة',
          variant: AppButtonVariant.primary,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _submit,
        ),
      ],
    );
  }

  Widget _buildCategoriesField(AsyncValue<List<ProductCategory>> async) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (error, stackTrace) => _buildLookupError('الفئات'),
      data: (List<ProductCategory> categories) {
        final Set<String> knownIds =
            categories.map((category) => category.id).toSet();
        final String? current = _categoryId;
        final String selected =
            (current != null && knownIds.contains(current))
                ? current
                : _noCategorySentinel;

        return DropdownButtonFormField<String>(
          value: selected,
          decoration: const InputDecoration(
            labelText: 'الفئة (اختياري)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: _noCategorySentinel,
              child: Text('بدون فئة'),
            ),
            ...categories.map(
              (category) => DropdownMenuItem<String>(
                value: category.id,
                child: Text(category.name),
              ),
            ),
          ],
          onChanged: _isSaving
              ? null
              : (value) {
                  setState(() {
                    if (value == null || value == _noCategorySentinel) {
                      _categoryId = null;
                    } else {
                      _categoryId = value;
                    }
                  });
                },
        );
      },
    );
  }

  Widget _buildUnitsField(AsyncValue<List<Unit>> async) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (error, stackTrace) => _buildLookupError('الوحدات'),
      data: (List<Unit> units) {
        final Set<String> knownIds = units.map((unit) => unit.id).toSet();
        final String? current = _defaultUnitId;
        final String? selected =
            (current != null && knownIds.contains(current)) ? current : null;

        return DropdownButtonFormField<String>(
          value: selected,
          hint: const Text('اختر الوحدة الأساسية'),
          decoration: const InputDecoration(
            labelText: 'الوحدة الأساسية',
            border: OutlineInputBorder(),
          ),
          items: units
              .map(
                (unit) => DropdownMenuItem<String>(
                  value: unit.id,
                  child: Text(unit.name),
                ),
              )
              .toList(),
          onChanged: _isSaving
              ? null
              : (value) {
                  setState(() {
                    _defaultUnitId = value;
                  });
                },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'الرجاء اختيار الوحدة الأساسية';
            }
            return null;
          },
        );
      },
    );
  }

  Widget _buildLookupError(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('تعذّر تحميل $label')),
        ],
      ),
    );
  }
}
