// lib/features/suppliers/presentation/pages/suppliers_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../purchases/presentation/dialogs/supplier_payment_dialog.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../providers/supplier_providers.dart';

/// Supplier management page.
///
/// Lists all suppliers of the currently selected company, and exposes
/// record-payment / create / edit / toggle-active / delete actions. All
/// actions go through [SuppliersNotifier], which delegates to the
/// repository and therefore to Row Level Security in the database.
class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Supplier>> suppliersAsync =
        ref.watch(suppliersProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('الموردون'),
        actions: <Widget>[
          IconButton(
            tooltip: 'إضافة مورد',
            onPressed: () => _openSupplierForm(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: suppliersAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الموردين',
          message: _errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.invalidate(suppliersProvider),
        ),
        data: (List<Supplier> suppliers) {
          final List<Supplier> filtered = _filter(suppliers, _searchQuery);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: AppTextField(
                  controller: _searchController,
                  hint: 'ابحث بالاسم أو الكود أو الهاتف',
                  prefixIcon: Icons.search,
                  onChanged: (String value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
              Expanded(
                child: suppliers.isEmpty
                    ? AppEmptyView(
                        icon: Icons.local_shipping_outlined,
                        title: 'لا يوجد موردون',
                        message:
                            'ابدأ بإضافة أول مورد للشركة (مَن تشتري منه).',
                        action: AppButton(
                          label: 'إضافة مورد',
                          icon: Icons.add,
                          onPressed: () => _openSupplierForm(context),
                        ),
                      )
                    : filtered.isEmpty
                        ? const AppEmptyView(
                            icon: Icons.search_off_outlined,
                            title: 'لا نتائج',
                            message: 'لم يُطابق أي مورد كلمة البحث.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder:
                                (BuildContext context, int index) {
                              final Supplier supplier = filtered[index];
                              return _SupplierCard(
                                supplier: supplier,
                                onRecordPayment: () =>
                                    _recordPayment(context, supplier),
                                onEdit: () => _openSupplierForm(
                                  context,
                                  existing: supplier,
                                ),
                                onToggleActive: () =>
                                    _toggleActive(context, supplier),
                                onDelete: () =>
                                    _confirmDelete(context, supplier),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  List<Supplier> _filter(List<Supplier> suppliers, String query) {
    final String trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return suppliers;
    }
    return suppliers.where((Supplier supplier) {
      final String name = supplier.name.toLowerCase();
      final String code = (supplier.code ?? '').toLowerCase();
      final String phone = (supplier.phone ?? '').toLowerCase();
      return name.contains(trimmed) ||
          code.contains(trimmed) ||
          phone.contains(trimmed);
    }).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _recordPayment(
    BuildContext context,
    Supplier supplier,
  ) async {
    await showSupplierPaymentDialog(
      context: context,
      supplierId: supplier.id,
      supplierName: supplier.name,
    );
  }

  Future<void> _openSupplierForm(
    BuildContext context, {
    Supplier? existing,
  }) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _SupplierFormDialog(
        existing: existing,
      ),
    );

    if (!context.mounted || saved != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null ? 'تم إضافة المورد' : 'تم تحديث المورد',
        ),
      ),
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    Supplier supplier,
  ) async {
    try {
      await ref.read(suppliersProvider.notifier).updateSupplier(
            supplierId: supplier.id,
            isActive: !supplier.isActive,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            supplier.isActive ? 'تم تعطيل المورد' : 'تم تفعيل المورد',
          ),
        ),
      );
    } on SupplierException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Supplier supplier,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('حذف المورد'),
        content: Text(
          'هل تريد حذف "${supplier.name}"؟ لا يمكن التراجع عن هذا الإجراء.',
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
      await ref.read(suppliersProvider.notifier).deleteSupplier(supplier.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المورد')),
      );
    } on SupplierException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error);
    }
  }
}

// -----------------------------------------------------------------------------
// Supplier card
// -----------------------------------------------------------------------------

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.onRecordPayment,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final Supplier supplier;
  final VoidCallback onRecordPayment;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isActive = supplier.isActive;
    final String? code = supplier.code;
    final String? phone = supplier.phone;
    final String? email = supplier.email;

    final List<String> meta = <String>[];
    if (code != null && code.isNotEmpty) {
      meta.add('كود: $code');
    }
    if (phone != null && phone.isNotEmpty) {
      meta.add(phone);
    } else if (email != null && email.isNotEmpty) {
      meta.add(email);
    }

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
                child: const Icon(Icons.local_shipping_outlined),
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
                            supplier.name,
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
                      meta.isEmpty ? 'لا توجد بيانات اتصال' : meta.join(' · '),
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_SupplierAction>(
                tooltip: 'خيارات',
                onSelected: (_SupplierAction action) {
                  switch (action) {
                    case _SupplierAction.recordPayment:
                      onRecordPayment();
                    case _SupplierAction.edit:
                      onEdit();
                    case _SupplierAction.toggleActive:
                      onToggleActive();
                    case _SupplierAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_SupplierAction>>[
                  const PopupMenuItem<_SupplierAction>(
                    value: _SupplierAction.recordPayment,
                    child: ListTile(
                      leading: Icon(Icons.payments_outlined),
                      title: Text('تسجيل دفعة'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<_SupplierAction>(
                    value: _SupplierAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('تعديل'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<_SupplierAction>(
                    value: _SupplierAction.toggleActive,
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
                  const PopupMenuItem<_SupplierAction>(
                    value: _SupplierAction.delete,
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

enum _SupplierAction { recordPayment, edit, toggleActive, delete }

// -----------------------------------------------------------------------------
// Form dialog
// -----------------------------------------------------------------------------

class _SupplierFormDialog extends ConsumerStatefulWidget {
  const _SupplierFormDialog({this.existing});

  /// When non-null the dialog is in edit mode; otherwise it creates a new
  /// supplier.
  final Supplier? existing;

  @override
  ConsumerState<_SupplierFormDialog> createState() =>
      _SupplierFormDialogState();
}

class _SupplierFormDialogState extends ConsumerState<_SupplierFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;

  bool _isSubmitting = false;
  SupplierFailureType? _failureType;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Supplier? existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _codeController = TextEditingController(text: existing?.code ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _emailController = TextEditingController(text: existing?.email ?? '');
    _addressController = TextEditingController(text: existing?.address ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
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

    setState(() => _isSubmitting = true);

    final SuppliersNotifier notifier = ref.read(suppliersProvider.notifier);
    final String name = _nameController.text.trim();
    final String? code = _emptyToNull(_codeController.text);
    final String? phone = _emptyToNull(_phoneController.text);
    final String? email = _emptyToNull(_emailController.text);
    final String? address = _emptyToNull(_addressController.text);
    final String? notes = _emptyToNull(_notesController.text);

    try {
      if (widget.existing == null) {
        await notifier.createSupplier(
          name: name,
          code: code,
          phone: phone,
          email: email,
          address: address,
          notes: notes,
        );
      } else {
        await notifier.updateSupplier(
          supplierId: widget.existing!.id,
          name: name,
          code: code,
          clearCode: code == null,
          phone: phone,
          clearPhone: phone == null,
          email: email,
          clearEmail: email == null,
          address: address,
          clearAddress: address == null,
          notes: notes,
          clearNotes: notes == null,
        );
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on SupplierException catch (error) {
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
        _failureType = SupplierFailureType.unknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SupplierFailureType? failure = _failureType;

    return AlertDialog(
      title: Text(_isEditMode ? 'تعديل مورد' : 'إضافة مورد'),
      content: SizedBox(
        width: 440,
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
                  label: 'اسم المورد',
                  hint: 'مثال: شركة الأمل للتوريدات',
                  enabled: !_isSubmitting,
                  autofocus: true,
                  validator: _validateName,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _codeController,
                  label: 'الكود — اختياري',
                  hint: 'مثال: SUP-001',
                  enabled: !_isSubmitting,
                  validator: _validateCode,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _phoneController,
                  label: 'الهاتف — اختياري',
                  hint: 'مثال: 01012345678',
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.phone,
                  validator: _validatePhone,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _emailController,
                  label: 'البريد الإلكتروني — اختياري',
                  hint: 'example@domain.com',
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _addressController,
                  label: 'العنوان — اختياري',
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  validator: _validateAddress,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _notesController,
                  label: 'ملاحظات — اختياري',
                  enabled: !_isSubmitting,
                  maxLines: 3,
                  validator: _validateNotes,
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
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _isEditMode ? 'حفظ' : 'إضافة',
          isLoading: _isSubmitting,
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
      backgroundColor: theme.colorScheme.surface,
      scrollable: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Validators
  // ---------------------------------------------------------------------------

  String? _validateName(String? value) {
    final ValidationError? error = Validators.firstError(<ValidationError?>[
      Validators.required(value),
      Validators.minLength(value, 1),
      Validators.maxLength(value, 200),
    ]);
    return error == null ? null : _validationMessage(error);
  }

  String? _validateCode(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 64) {
      return 'الكود طويل جدًا (الحد الأقصى 64 حرفًا)';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 30) {
      return 'رقم الهاتف طويل جدًا (الحد الأقصى 30 حرفًا)';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final ValidationError? error = Validators.email(trimmed);
    return error == null ? null : _validationMessage(error);
  }

  String? _validateAddress(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 500) {
      return 'العنوان طويل جدًا (الحد الأقصى 500 حرف)';
    }
    return null;
  }

  String? _validateNotes(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length > 2000) {
      return 'الملاحظات طويلة جدًا (الحد الأقصى 2000 حرف)';
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

void _showError(BuildContext context, SupplierException error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_failureMessage(error.type))),
  );
}

String _errorMessage(Object error) {
  if (error is SupplierException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(SupplierFailureType type) => switch (type) {
      SupplierFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      SupplierFailureType.unauthorized =>
        'انتهت صلاحية الجلسة أو لا تملك صلاحية. يرجى تسجيل الدخول مجددًا.',
      SupplierFailureType.notFound =>
        'المورد المطلوب غير موجود أو تم حذفه.',
      SupplierFailureType.nameConflict =>
        'يوجد مورد آخر بنفس الاسم في هذه الشركة.',
      SupplierFailureType.codeConflict =>
        'يوجد مورد آخر بنفس الكود في هذه الشركة.',
      SupplierFailureType.phoneConflict =>
        'يوجد مورد آخر بنفس رقم الهاتف في هذه الشركة.',
      SupplierFailureType.inUse =>
        'لا يمكن حذف المورد لوجود سجلات مرتبطة به. يمكنك تعطيله بدلًا من ذلك.',
      SupplierFailureType.invalidResponse =>
        'تعذّر قراءة بيانات الموردين. يرجى المحاولة لاحقًا.',
      SupplierFailureType.unknown =>
        'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.',
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
