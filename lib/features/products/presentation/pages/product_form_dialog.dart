// lib/features/products/presentation/pages/product_units_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_unit.dart';
import '../../domain/entities/unit.dart';
import '../../domain/repositories/product_repository.dart';
import '../providers/product_providers.dart';
import '../providers/unit_providers.dart';

/// Opens the dialog that manages non-base unit conversions of a product.
///
/// Example: a product whose base unit is "piece" can also be sold in
/// "carton" where 1 carton = 24 pieces. Those relationships are managed
/// here. The product's base unit itself is edited in the product form, not
/// in this dialog.
Future<void> showProductUnitsDialog({
  required BuildContext context,
  required Product product,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) =>
        _ProductUnitsDialog(product: product),
  );
}

class _ProductUnitsDialog extends ConsumerWidget {
  const _ProductUnitsDialog({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProductUnit>> unitsAsync =
        ref.watch(productUnitsProvider(product.id));
    final AsyncValue<List<Unit>> availableUnitsAsync =
        ref.watch(unitsProvider);

    return AlertDialog(
      title: Text('وحدات إضافية — ${product.name}'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: unitsAsync.when(
          loading: () => const AppLoader(),
          error: (Object error, StackTrace _) => AppErrorView(
            title: 'تعذّر تحميل الوحدات',
            message: _errorMessage(error),
            retryLabel: 'إعادة المحاولة',
            onRetry: () =>
                ref.invalidate(productUnitsProvider(product.id)),
          ),
          data: (List<ProductUnit> productUnits) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: productUnits.isEmpty
                      ? const AppEmptyView(
                          icon: Icons.swap_horiz_outlined,
                          title: 'لا توجد وحدات إضافية',
                          message:
                              'يمكنك إضافة وحدات بديلة لهذا المنتج '
                              '(مثل: كرتونة، دستة) مع معامل التحويل.',
                        )
                      : ListView.separated(
                          itemCount: productUnits.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (BuildContext context, int index) {
                            final ProductUnit productUnit =
                                productUnits[index];
                            return availableUnitsAsync.when(
                              data: (List<Unit> units) {
                                final String unitName = _resolveUnitName(
                                  units,
                                  productUnit.unitId,
                                );
                                return _ProductUnitCard(
                                  productUnit: productUnit,
                                  unitName: unitName,
                                  onEdit: () => _openEditForm(
                                    context,
                                    ref,
                                    productUnit,
                                    units,
                                  ),
                                  onDelete: () => _confirmDelete(
                                    context,
                                    ref,
                                    productUnit,
                                  ),
                                );
                              },
                              loading: () => const Padding(
                                padding: EdgeInsets.all(8),
                                child: LinearProgressIndicator(),
                              ),
                              error: (Object _, StackTrace __) =>
                                  _buildLookupError(context),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    label: 'إضافة وحدة',
                    icon: Icons.add,
                    variant: AppButtonVariant.secondary,
                    onPressed: availableUnitsAsync.maybeWhen(
                      data: (List<Unit> units) => units.isEmpty
                          ? null
                          : () => _openAddForm(context, ref, units),
                      orElse: () => null,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: 'إغلاق',
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      scrollable: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openAddForm(
    BuildContext context,
    WidgetRef ref,
    List<Unit> units,
  ) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _ProductUnitFormDialog(
        productId: product.id,
        baseUnitId: product.defaultUnitId,
        availableUnits: units,
      ),
    );
  }

  Future<void> _openEditForm(
    BuildContext context,
    WidgetRef ref,
    ProductUnit productUnit,
    List<Unit> units,
  ) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _ProductUnitFormDialog(
        productId: product.id,
        baseUnitId: product.defaultUnitId,
        availableUnits: units,
        existing: productUnit,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ProductUnit productUnit,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف الوحدة الإضافية'),
        content: const Text(
          'هل تريد حذف هذه الوحدة الإضافية؟ لا يمكن التراجع.',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'حذف',
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
      await ref
          .read(productUnitsProvider(product.id).notifier)
          .deleteProductUnit(productUnit.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الوحدة الإضافية')),
      );
    } on ProductException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }
}

// -----------------------------------------------------------------------------
// Unit card
// -----------------------------------------------------------------------------

class _ProductUnitCard extends StatelessWidget {
  const _ProductUnitCard({
    required this.productUnit,
    required this.unitName,
    required this.onEdit,
    required this.onDelete,
  });

  final ProductUnit productUnit;
  final String unitName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String factorLabel = _formatFactor(productUnit.conversionFactor);

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.swap_horiz_outlined, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(unitName, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '1 $unitName = $factorLabel وحدة أساسية',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatFactor(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

// -----------------------------------------------------------------------------
// Add / edit form
// -----------------------------------------------------------------------------

class _ProductUnitFormDialog extends ConsumerStatefulWidget {
  const _ProductUnitFormDialog({
    required this.productId,
    required this.baseUnitId,
    required this.availableUnits,
    this.existing,
  });

  final String productId;
  final String baseUnitId;
  final List<Unit> availableUnits;
  final ProductUnit? existing;

  @override
  ConsumerState<_ProductUnitFormDialog> createState() =>
      _ProductUnitFormDialogState();
}

class _ProductUnitFormDialogState
    extends ConsumerState<_ProductUnitFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _factorController;
  String? _unitId;

  bool _isSubmitting = false;
  ProductFailureType? _failureType;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ProductUnit? existing = widget.existing;
    _factorController = TextEditingController(
      text: existing == null ? '' : _formatFactor(existing.conversionFactor),
    );
    _unitId = existing?.unitId;
  }

  @override
  void dispose() {
    _factorController.dispose();
    super.dispose();
  }

  static String _formatFactor(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// Units eligible for this conversion: those that are not the product's
  /// base unit. In edit mode, the currently selected unit stays visible.
  List<Unit> _eligibleUnits() {
    final List<Unit> filtered = widget.availableUnits
        .where((Unit unit) => unit.id != widget.baseUnitId)
        .toList(growable: false);

    if (_isEditing) {
      final String? currentId = widget.existing!.unitId;
      final bool present = filtered.any((Unit unit) => unit.id == currentId);
      if (!present) {
        final Unit? current = widget.availableUnits
            .where((Unit unit) => unit.id == currentId)
            .firstOrNull;
        if (current != null) {
          return <Unit>[current, ...filtered];
        }
      }
    }
    return filtered;
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

    final String? unitId = _unitId;
    if (unitId == null || unitId.isEmpty) {
      setState(() => _failureType = ProductFailureType.unitNotFound);
      return;
    }

    final double? factor = double.tryParse(_factorController.text.trim());
    if (factor == null || factor <= 0) {
      setState(() => _failureType = ProductFailureType.invalidResponse);
      return;
    }

    setState(() => _isSubmitting = true);

    final ProductUnitsNotifier notifier =
        ref.read(productUnitsProvider(widget.productId).notifier);

    try {
      if (_isEditing) {
        await notifier.updateProductUnit(
          productUnitId: widget.existing!.id,
          conversionFactor: factor,
        );
      } else {
        await notifier.addProductUnit(
          unitId: unitId,
          conversionFactor: factor,
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
    final ThemeData theme = Theme.of(context);
    final ProductFailureType? failure = _failureType;
    final List<Unit> eligible = _eligibleUnits();

    return AlertDialog(
      title: Text(_isEditing ? 'تعديل الوحدة الإضافية' : 'إضافة وحدة إضافية'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _unitId,
                isExpanded: true,
                hint: const Text('اختر الوحدة'),
                decoration: const InputDecoration(
                  labelText: 'الوحدة',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final Unit unit in eligible)
                    DropdownMenuItem<String>(
                      value: unit.id,
                      child: Text(unit.name),
                    ),
                ],
                onChanged: _isSubmitting || _isEditing
                    ? null
                    : (String? value) {
                        setState(() => _unitId = value);
                      },
                validator: (String? value) {
                  if (value == null || value.isEmpty) {
                    return 'الرجاء اختيار الوحدة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _factorController,
                label: 'معامل التحويل (عدد الوحدات الأساسية)',
                hint: 'مثال: 24',
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (String? value) {
                  final String trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'الرجاء إدخال معامل التحويل';
                  }
                  final double? parsed = double.tryParse(trimmed);
                  if (parsed == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  if (parsed <= 0) {
                    return 'يجب أن يكون المعامل أكبر من صفر';
                  }
                  return null;
                },
              ),
              if (failure != null) ...<Widget>[
                const SizedBox(height: 12),
                _FailureBanner(message: _failureMessage(failure)),
              ],
            ],
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
          label: _isEditing ? 'حفظ' : 'إضافة',
          isLoading: _isSubmitting,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
      backgroundColor: theme.colorScheme.surface,
      scrollable: false,
    );
  }
}

// -----------------------------------------------------------------------------
// Helpers
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

String _resolveUnitName(List<Unit> units, String unitId) {
  for (final Unit unit in units) {
    if (unit.id == unitId) {
      return unit.name;
    }
  }
  return 'وحدة غير معروفة';
}

Widget _buildLookupError(BuildContext context) {
  final ColorScheme scheme = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: <Widget>[
        Icon(Icons.error_outline, color: scheme.error, size: 20),
        const SizedBox(width: 8),
        const Expanded(child: Text('تعذّر تحميل الوحدات')),
      ],
    ),
  );
}

String _errorMessage(Object error) {
  if (error is ProductException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

void _showError(BuildContext context, ProductException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _failureMessage(ProductFailureType type) => switch (type) {
      ProductFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      ProductFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      ProductFailureType.notFound => 'السجل المطلوب غير موجود.',
      ProductFailureType.skuConflict =>
        'يوجد تعارض في الـ SKU. يرجى تحديث الصفحة.',
      ProductFailureType.barcodeConflict =>
        'يوجد تعارض في الباركود. يرجى تحديث الصفحة.',
      ProductFailureType.categoryNotFound => 'التصنيف غير متاح.',
      ProductFailureType.unitNotFound => 'الرجاء اختيار وحدة صحيحة.',
      ProductFailureType.inUse =>
        'لا يمكن إتمام العملية لوجود سجلات مرتبطة.',
      ProductFailureType.invalidResponse =>
        'القيمة غير صحيحة. تأكد من معامل التحويل.',
      ProductFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
    };
