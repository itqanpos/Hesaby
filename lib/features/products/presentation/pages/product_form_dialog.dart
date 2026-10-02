// lib/features/products/presentation/pages/product_form_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/unit.dart';
import '../../domain/repositories/product_repository.dart';
import '../providers/category_providers.dart';
import '../providers/product_providers.dart';
import '../providers/unit_providers.dart';

/// Opens the product create / edit dialog.
///
/// Pass [existing] to edit an existing product, or leave it `null` to create
/// a new one. Returns `true` when the product was saved, `false` when the
/// user cancelled, and `null` when the dialog was dismissed.
Future<bool?> showProductFormDialog({
  required BuildContext context,
  required WidgetRef ref,
  Product? existing,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => _ProductFormDialog(existing: existing),
  );
}

class _ProductFormDialog extends ConsumerStatefulWidget {
  const _ProductFormDialog({this.existing});

  /// When non-null, the dialog is in edit mode.
  final Product? existing;

  @override
  ConsumerState<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _descriptionController;

  String? _categoryId;
  String? _defaultUnitId;
  bool _isActive = true;

  bool _isSubmitting = false;
  ProductFailureType? _failureType;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Product? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _skuController = TextEditingController(text: existing?.sku ?? '');
    _barcodeController = TextEditingController(text: existing?.barcode ?? '');
    _sellingPriceController = TextEditingController(
      text: existing == null ? '' : _formatNumber(existing.sellingPrice),
    );
    _costPriceController = TextEditingController(
      text: existing == null ? '' : _formatNumber(existing.costPrice),
    );
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _categoryId = existing?.categoryId;
    _defaultUnitId = existing?.defaultUnitId;
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_failureType != null) {
      setState(() => _failureType = null);
    }

    final bool isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final String? unitId = _defaultUnitId;
    if (unitId == null || unitId.isEmpty) {
      setState(() {
        _failureType = ProductFailureType.unitNotFound;
      });
      return;
    }

    final double? sellingPrice =
        double.tryParse(_sellingPriceController.text.trim());
    final double? costPrice = double.tryParse(_costPriceController.text.trim());
    if (sellingPrice == null || costPrice == null) {
      setState(() {
        _failureType = ProductFailureType.invalidResponse;
      });
      return;
    }

    setState(() => _isSubmitting = true);

    final ProductsNotifier notifier = ref.read(productsProvider.notifier);
    final String name = _nameController.text.trim();
    final String? sku = _emptyToNull(_skuController.text);
    final String? barcode = _emptyToNull(_barcodeController.text);
    final String? description = _emptyToNull(_descriptionController.text);

    try {
      if (widget.existing == null) {
        final CompanyContextState context = ref.read(companyContextProvider);
        final String? companyId = context.currentCompany?.id;
        if (companyId == null) {
          throw const ProductException(
            type: ProductFailureType.unauthorized,
            cause: 'No company is currently selected.',
          );
        }

        await notifier.createProduct(
          companyId: companyId,
          name: name,
          defaultUnitId: unitId,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          categoryId: _categoryId,
          sku: sku,
          barcode: barcode,
          description: description,
        );
      } else {
        await notifier.updateProduct(
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
          isActive: _isActive,
        );
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on ProductException catch (error) {
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
        _failureType = ProductFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ProductCategory>> categoriesAsync =
        ref.watch(categoriesProvider);
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);
    final ProductFailureType? failure = _failureType;

    return AlertDialog(
      title: Text(_isEditing ? 'تعديل منتج' : 'إضافة منتج'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppTextField(
                  controller: _nameController,
                  label: 'اسم المنتج',
                  hint: 'مثال: بيبسي 1 لتر',
                  enabled: !_isSubmitting,
                  autofocus: true,
                  validator: (String? value) => _validateRequired(
                    value,
                    'اسم المنتج',
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _skuController,
                  label: 'رمز المنتج (SKU) — اختياري',
                  enabled: !_isSubmitting,
                  validator: _validateSku,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _barcodeController,
                  label: 'الباركود — اختياري',
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.number,
                  validator: _validateBarcode,
                ),
                const SizedBox(height: 12),
                categoriesAsync.when(
                  data: (List<ProductCategory> categories) =>
                      _buildCategoryField(categories),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                  error: (Object _, StackTrace __) => _buildLookupError('الفئات'),
                ),
                const SizedBox(height: 12),
                unitsAsync.when(
                  data: (List<Unit> units) => _buildUnitField(units),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                  error: (Object _, StackTrace __) => _buildLookupError('الوحدات'),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _sellingPriceController,
                  label: 'سعر البيع',
                  enabled: !_isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _validatePrice,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _costPriceController,
                  label: 'سعر التكلفة',
                  enabled: !_isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _validatePrice,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _descriptionController,
                  label: 'الوصف — اختياري',
                  enabled: !_isSubmitting,
                  maxLines: 3,
                  validator: _validateDescription,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('نشط'),
                  value: _isActive,
                  onChanged: _isSubmitting
                      ? null
                      : (bool value) {
                          setState(() => _isActive = value);
                        },
                ),
                if (failure != null) ...<Widget>[
                  const SizedBox(height: 8),
                  _FailureBanner(message: _failureMessage(failure)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'إلغاء',
          variant: AppButtonVariant.text,
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _isEditing ? 'حفظ التعديلات' : 'إضافة',
          isLoading: _isSubmitting,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
      scrollable: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Field builders
  // ---------------------------------------------------------------------------

  Widget _buildCategoryField(List<ProductCategory> categories) {
    final Set<String> knownIds =
        categories.map((ProductCategory category) => category.id).toSet();
    final String? current = _categoryId;
    final String? selected =
        (current != null && knownIds.contains(current)) ? current : null;

    return DropdownButtonFormField<String?>(
      initialValue: selected,
      decoration: const InputDecoration(
        labelText: 'الفئة — اختياري',
        border: OutlineInputBorder(),
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
    final Set<String> knownIds =
        units.map((Unit unit) => unit.id).toSet();
    final String? current = _defaultUnitId;
    final String? selected =
        (current != null && knownIds.contains(current)) ? current : null;

    return DropdownButtonFormField<String>(
      initialValue: selected,
      hint: const Text('اختر الوحدة الأساسية'),
      decoration: const InputDecoration(
        labelText: 'الوحدة الأساسية',
        border: OutlineInputBorder(),
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
          return 'الرجاء اختيار الوحدة الأساسية';
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
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 64) {
      return 'الرمز طويل جدًا (الحد الأقصى 64 حرفًا)';
    }
    return null;
  }

  String? _validateBarcode(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 64) {
      return 'الباركود طويل جدًا (الحد الأقصى 64 حرفًا)';
    }
    return null;
  }

  String? _validateDescription(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
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
}

// -----------------------------------------------------------------------------
// Inline error banner
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
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
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
      ProductFailureType.unitNotFound =>
        'الرجاء اختيار الوحدة الأساسية.',
      ProductFailureType.inUse =>
        'لا يمكن حذف المنتج لوجود سجلات مرتبطة به.',
      ProductFailureType.invalidResponse =>
        'الرجاء إدخال أسعار صحيحة.',
      ProductFailureType.unknown =>
        'تعذّر حفظ المنتج. يرجى المحاولة مرة أخرى.',
    };
