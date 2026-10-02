// lib/features/products/presentation/pages/categories_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../providers/category_providers.dart';

/// Category management page.
///
/// Lists all categories of the currently selected company, and exposes
/// create / edit / toggle-active / delete actions. All actions go through
/// [CategoriesNotifier], which delegates to the repository and therefore to
/// Row Level Security in the database.
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProductCategory>> categoriesAsync =
        ref.watch(categoriesProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('التصنيفات'),
        actions: <Widget>[
          IconButton(
            tooltip: 'إضافة تصنيف',
            onPressed: () => _openCategoryForm(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل التصنيفات',
          message: _errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
        data: (List<ProductCategory> categories) {
          if (categories.isEmpty) {
            return AppEmptyView(
              icon: Icons.category_outlined,
              title: 'لا توجد تصنيفات',
              message: 'ابدأ بإضافة أول تصنيف لمنتجاتك.',
              action: AppButton(
                label: 'إضافة تصنيف',
                icon: Icons.add,
                onPressed: () => _openCategoryForm(context, ref),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final ProductCategory category = categories[index];
              return _CategoryCard(
                category: category,
                onEdit: () =>
                    _openCategoryForm(context, ref, category: category),
                onToggleActive: () => _toggleActive(context, ref, category),
                onDelete: () => _confirmDelete(context, ref, category),
              );
            },
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openCategoryForm(
    BuildContext context,
    WidgetRef ref, {
    ProductCategory? category,
  }) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _CategoryFormDialog(
        existing: category,
        onSubmit: (
          String name,
          String? description,
          int sortOrder,
        ) async {
          final CategoriesNotifier notifier =
              ref.read(categoriesProvider.notifier);
          if (category == null) {
            await notifier.createCategory(
              name: name,
              description: description,
              sortOrder: sortOrder,
            );
          } else {
            await notifier.updateCategory(
              categoryId: category.id,
              name: name,
              description: description,
              clearDescription: description == null,
              sortOrder: sortOrder,
            );
          }
        },
      ),
    );

    if (!context.mounted || saved != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          category == null ? 'تم إضافة التصنيف' : 'تم تحديث التصنيف',
        ),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    ProductCategory category,
  ) async {
    try {
      await ref.read(categoriesProvider.notifier).updateCategory(
            categoryId: category.id,
            isActive: !category.isActive,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            category.isActive ? 'تم تعطيل التصنيف' : 'تم تفعيل التصنيف',
          ),
        ),
      );
    } on CategoryException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ProductCategory category,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف التصنيف'),
        content: Text(
          'هل تريد حذف "${category.name}"؟ لا يمكن التراجع عن هذا الإجراء.',
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
      await ref.read(categoriesProvider.notifier).deleteCategory(category.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف التصنيف')),
      );
    } on CategoryException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }
}

// -----------------------------------------------------------------------------
// Card
// -----------------------------------------------------------------------------

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final ProductCategory category;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? description = category.description;
    final bool isActive = category.isActive;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: isActive
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                foregroundColor: isActive
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                child: Text(
                  category.name.characters.first.toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            category.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'معطّل',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description ?? 'بدون وصف',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_CategoryAction>(
                tooltip: 'خيارات',
                onSelected: (_CategoryAction action) {
                  switch (action) {
                    case _CategoryAction.edit:
                      onEdit();
                    case _CategoryAction.toggleActive:
                      onToggleActive();
                    case _CategoryAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_CategoryAction>>[
                  const PopupMenuItem<_CategoryAction>(
                    value: _CategoryAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('تعديل'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_CategoryAction>(
                    value: _CategoryAction.toggleActive,
                    child: ListTile(
                      leading: Icon(
                        isActive
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      title: Text(isActive ? 'تعطيل' : 'تفعيل'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem<_CategoryAction>(
                    value: _CategoryAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('حذف'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CategoryAction { edit, toggleActive, delete }

// -----------------------------------------------------------------------------
// Form dialog
// -----------------------------------------------------------------------------

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({
    required this.existing,
    required this.onSubmit,
  });

  /// When non-null the dialog is in edit mode; otherwise it creates a new
  /// category.
  final ProductCategory? existing;

  /// Persists the form. Throws [CategoryException] on failure.
  final Future<void> Function(
    String name,
    String? description,
    int sortOrder,
  ) onSubmit;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _sortOrderController;

  bool _isSubmitting = false;
  CategoryFailureType? _failureType;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ProductCategory? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _sortOrderController = TextEditingController(
      text: existing?.sortOrder.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _sortOrderController.dispose();
    super.dispose();
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

    setState(() => _isSubmitting = true);

    final String name = _nameController.text.trim();
    final String descriptionRaw = _descriptionController.text.trim();
    final String? description = descriptionRaw.isEmpty ? null : descriptionRaw;
    final int sortOrder = int.tryParse(_sortOrderController.text.trim()) ?? 0;

    try {
      await widget.onSubmit(name, description, sortOrder);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on CategoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
        _failureType = error.type;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CategoryFailureType? failure = _failureType;

    return AlertDialog(
      title: Text(_isEditMode ? 'تعديل التصنيف' : 'إضافة تصنيف'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppTextField(
                  controller: _nameController,
                  label: 'اسم التصنيف',
                  hint: 'مثال: مشروبات',
                  enabled: !_isSubmitting,
                  autofocus: true,
                  validator: _validateName,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _descriptionController,
                  label: 'الوصف (اختياري)',
                  hint: 'وصف مختصر للتصنيف',
                  enabled: !_isSubmitting,
                  maxLines: 3,
                  validator: _validateDescription,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _sortOrderController,
                  label: 'ترتيب العرض',
                  hint: '0',
                  keyboardType: TextInputType.number,
                  enabled: !_isSubmitting,
                  validator: _validateSortOrder,
                ),
                if (failure != null) ...<Widget>[
                  const SizedBox(height: 12),
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
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _isEditMode ? 'حفظ' : 'إضافة',
          isLoading: _isSubmitting,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
      // `Material` color from the theme is used; extra padding balances the
      // dialog when text scale is large.
      scrollable: false,
      backgroundColor: theme.colorScheme.surface,
    );
  }

  String? _validateName(String? value) {
    final ValidationError? error = Validators.firstError(<ValidationError?>[
      Validators.required(value),
      Validators.minLength(value, 1),
      Validators.maxLength(value, 200),
    ]);
    return error == null ? null : _validationMessage(error);
  }

  String? _validateDescription(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 500) {
      return 'الوصف طويل جدًا (الحد الأقصى 500 حرف)';
    }
    return null;
  }

  String? _validateSortOrder(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (int.tryParse(trimmed) == null) {
      return 'يجب إدخال رقم صحيح';
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
  if (error is CategoryException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

void _showError(BuildContext context, CategoryException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _failureMessage(CategoryFailureType type) => switch (type) {
      CategoryFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      CategoryFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      CategoryFailureType.notFound =>
        'التصنيف المطلوب غير موجود أو تم حذفه.',
      CategoryFailureType.nameConflict =>
        'يوجد تصنيف بنفس الاسم في هذه الشركة.',
      CategoryFailureType.inUse =>
        'لا يمكن حذف التصنيف لوجود منتجات مرتبطة به. يمكنك تعطيله بدلًا من ذلك.',
      CategoryFailureType.invalidResponse =>
        'تعذّر قراءة بيانات التصنيفات. يرجى المحاولة لاحقًا.',
      CategoryFailureType.unknown =>
        'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.',
    };

String _validationMessage(ValidationError error) => switch (error) {
      ValidationError.required => 'هذا الحقل مطلوب',
      ValidationError.invalidEmail => 'صيغة البريد الإلكتروني غير صحيحة',
      ValidationError.invalidPhone => 'صيغة رقم الهاتف غير صحيحة',
      ValidationError.tooShort => 'القيمة قصيرة جدًا',
      ValidationError.tooLong => 'القيمة طويلة جدًا',
      ValidationError.invalidNumber => 'يجب إدخال رقم صحيح',
      ValidationError.mustBePositive => 'يجب أن تكون القيمة موجبة',
    };
