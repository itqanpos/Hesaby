// lib/features/products/presentation/pages/units_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/unit.dart';
import '../../domain/repositories/unit_repository.dart';
import '../providers/unit_providers.dart';

/// Unit management page.
///
/// Lists all units of the currently selected company, and exposes
/// create / edit / toggle-active / delete actions. All actions go through
/// [UnitsNotifier], which delegates to the repository and therefore to Row
/// Level Security in the database.
class UnitsPage extends ConsumerWidget {
  const UnitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Unit>> unitsAsync = ref.watch(unitsProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('الوحدات'),
        actions: <Widget>[
          IconButton(
            tooltip: 'إضافة وحدة',
            onPressed: () => _openUnitForm(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: unitsAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الوحدات',
          message: _errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.invalidate(unitsProvider),
        ),
        data: (List<Unit> units) {
          if (units.isEmpty) {
            return AppEmptyView(
              icon: Icons.straighten_outlined,
              title: 'لا توجد وحدات',
              message: 'ابدأ بإضافة أول وحدة لقياس منتجاتك (قطعة، كرتونة، ...).',
              action: AppButton(
                label: 'إضافة وحدة',
                icon: Icons.add,
                onPressed: () => _openUnitForm(context, ref),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: units.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final Unit unit = units[index];
              return _UnitCard(
                unit: unit,
                onEdit: () => _openUnitForm(context, ref, unit: unit),
                onToggleActive: () => _toggleActive(context, ref, unit),
                onDelete: () => _confirmDelete(context, ref, unit),
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

  Future<void> _openUnitForm(
    BuildContext context,
    WidgetRef ref, {
    Unit? unit,
  }) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _UnitFormDialog(
        existing: unit,
        onSubmit: (String name, String? symbol) async {
          final UnitsNotifier notifier = ref.read(unitsProvider.notifier);
          if (unit == null) {
            await notifier.createUnit(name: name, symbol: symbol);
          } else {
            await notifier.updateUnit(
              unitId: unit.id,
              name: name,
              symbol: symbol,
              clearSymbol: symbol == null,
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
        content: Text(unit == null ? 'تم إضافة الوحدة' : 'تم تحديث الوحدة'),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Unit unit,
  ) async {
    try {
      await ref.read(unitsProvider.notifier).updateUnit(
            unitId: unit.id,
            isActive: !unit.isActive,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(unit.isActive ? 'تم تعطيل الوحدة' : 'تم تفعيل الوحدة'),
        ),
      );
    } on UnitException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Unit unit,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف الوحدة'),
        content: Text(
          'هل تريد حذف "${unit.name}"؟ لا يمكن التراجع عن هذا الإجراء.',
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
      await ref.read(unitsProvider.notifier).deleteUnit(unit.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الوحدة')),
      );
    } on UnitException catch (error) {
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

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final Unit unit;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? symbol = unit.symbol;
    final bool isActive = unit.isActive;

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
                child: const Icon(Icons.straighten_outlined),
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
                            unit.name,
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
                      symbol ?? 'بدون رمز',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_UnitAction>(
                tooltip: 'خيارات',
                onSelected: (_UnitAction action) {
                  switch (action) {
                    case _UnitAction.edit:
                      onEdit();
                    case _UnitAction.toggleActive:
                      onToggleActive();
                    case _UnitAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_UnitAction>>[
                  const PopupMenuItem<_UnitAction>(
                    value: _UnitAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('تعديل'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_UnitAction>(
                    value: _UnitAction.toggleActive,
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
                  const PopupMenuItem<_UnitAction>(
                    value: _UnitAction.delete,
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

enum _UnitAction { edit, toggleActive, delete }

// -----------------------------------------------------------------------------
// Form dialog
// -----------------------------------------------------------------------------

class _UnitFormDialog extends StatefulWidget {
  const _UnitFormDialog({
    required this.existing,
    required this.onSubmit,
  });

  /// When non-null the dialog is in edit mode; otherwise it creates a new
  /// unit.
  final Unit? existing;

  /// Persists the form. Throws [UnitException] on failure.
  final Future<void> Function(String name, String? symbol) onSubmit;

  @override
  State<_UnitFormDialog> createState() => _UnitFormDialogState();
}

class _UnitFormDialogState extends State<_UnitFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _symbolController;

  bool _isSubmitting = false;
  UnitFailureType? _failureType;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Unit? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _symbolController = TextEditingController(text: existing?.symbol ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _symbolController.dispose();
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
    final String symbolRaw = _symbolController.text.trim();
    final String? symbol = symbolRaw.isEmpty ? null : symbolRaw;

    try {
      await widget.onSubmit(name, symbol);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on UnitException catch (error) {
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
    final UnitFailureType? failure = _failureType;

    return AlertDialog(
      title: Text(_isEditMode ? 'تعديل الوحدة' : 'إضافة وحدة'),
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
                  label: 'اسم الوحدة',
                  hint: 'مثال: قطعة',
                  enabled: !_isSubmitting,
                  autofocus: true,
                  validator: _validateName,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _symbolController,
                  label: 'الرمز (اختياري)',
                  hint: 'مثال: kg، L، pcs',
                  enabled: !_isSubmitting,
                  validator: _validateSymbol,
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
      scrollable: false,
      backgroundColor: theme.colorScheme.surface,
    );
  }

  String? _validateName(String? value) {
    final ValidationError? error = Validators.firstError(<ValidationError?>[
      Validators.required(value),
      Validators.minLength(value, 1),
      Validators.maxLength(value, 100),
    ]);
    return error == null ? null : _validationMessage(error);
  }

  String? _validateSymbol(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 20) {
      return 'الرمز طويل جدًا (الحد الأقصى 20 حرفًا)';
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
  if (error is UnitException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

void _showError(BuildContext context, UnitException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _failureMessage(UnitFailureType type) => switch (type) {
      UnitFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      UnitFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      UnitFailureType.notFound =>
        'الوحدة المطلوبة غير موجودة أو تم حذفها.',
      UnitFailureType.nameConflict =>
        'يوجد وحدة بنفس الاسم في هذه الشركة.',
      UnitFailureType.symbolConflict =>
        'يوجد وحدة بنفس الرمز في هذه الشركة.',
      UnitFailureType.inUse =>
        'لا يمكن حذف الوحدة لوجود منتجات أو تحويلات مرتبطة بها. يمكنك تعطيلها بدلًا من ذلك.',
      UnitFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الوحدات. يرجى المحاولة لاحقًا.',
      UnitFailureType.unknown =>
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
