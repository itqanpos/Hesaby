// lib/features/companies/presentation/pages/branch_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/branch.dart';
import '../../domain/repositories/company_repository.dart';
import '../providers/company_context_provider.dart';

/// Branch creation / edit form.
///
/// When [branchId] is `null` the form runs in creation mode and starts
/// blank. When [branchId] is supplied the form looks the branch up in
/// [companyAllBranchesProvider] and pre-fills the fields, showing a loader
/// while the list is being fetched.
class BranchFormPage extends ConsumerStatefulWidget {
  const BranchFormPage({super.key, this.branchId});

  /// Identifier of the branch being edited, or `null` for creation mode.
  final String? branchId;

  @override
  ConsumerState<BranchFormPage> createState() => _BranchFormPageState();
}

class _BranchFormPageState extends ConsumerState<BranchFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;

  bool _initialized = false;
  bool _isSaving = false;
  CompanyFailureType? _saveFailure;

  bool get _isEditMode => widget.branchId != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _codeController = TextEditingController();
    _addressController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Hydration
  // ---------------------------------------------------------------------------

  void _hydrateFrom(Branch branch) {
    if (_initialized) return;
    _initialized = true;
    _nameController.text = branch.name;
    _codeController.text = branch.code ?? '';
    _addressController.text = branch.address ?? '';
    _phoneController.text = branch.phone ?? '';
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (_saveFailure != null) {
      setState(() => _saveFailure = null);
    }

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _isSaving = true);

    final String name = _nameController.text.trim();
    final String? code = _emptyToNull(_codeController.text);
    final String? address = _emptyToNull(_addressController.text);
    final String? phone = _emptyToNull(_phoneController.text);

    try {
      final CompanyContextNotifier notifier =
          ref.read(companyContextProvider.notifier);

      if (_isEditMode) {
        await notifier.updateBranch(
          branchId: widget.branchId!,
          name: name,
          code: code,
          address: address,
          phone: phone,
        );
      } else {
        await notifier.createBranch(
          name: name,
          code: code,
          address: address,
          phone: phone,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _isEditMode
                  ? 'تم حفظ تعديلات الفرع.'
                  : 'تمت إضافة الفرع.',
            ),
          ),
        );
      if (context.mounted) {
        context.pop();
      }
    } on CompanyException catch (error) {
      if (!mounted) return;
      setState(() => _saveFailure = error.type);
    } on Object {
      if (!mounted) return;
      setState(() => _saveFailure = CompanyFailureType.unknown);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  static String? _emptyToNull(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ---------------------------------------------------------------------------
  // Validators
  // ---------------------------------------------------------------------------

  String? _validateName(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'الرجاء إدخال اسم الفرع';
    }
    if (trimmed.length > 200) {
      return 'الاسم طويل جدًا (الحد الأقصى 200 حرف)';
    }
    return null;
  }

  String? _validateCode(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 32) {
      return 'الكود طويل جدًا (الحد الأقصى 32 حرف)';
    }
    return null;
  }

  String? _validateOptional(
    String? value,
    int maxLength,
    String label,
  ) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > maxLength) {
      return '$label طويل جدًا (الحد الأقصى $maxLength حرف)';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AppShell(
      appBar: AppBar(
        title: Text(_isEditMode ? 'تعديل الفرع' : 'إضافة فرع'),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_isEditMode) {
      _initialized = true;
      return _buildForm(context);
    }

    final AsyncValue<List<Branch>> branchesAsync =
        ref.watch(companyAllBranchesProvider);

    return branchesAsync.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace _) => AppErrorView(
        title: 'تعذّر تحميل بيانات الفرع',
        message: _errorMessage(error),
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.invalidate(companyAllBranchesProvider),
      ),
      data: (List<Branch> branches) {
        Branch? existing;
        for (final Branch candidate in branches) {
          if (candidate.id == widget.branchId) {
            existing = candidate;
            break;
          }
        }
        if (existing == null) {
          return const AppEmptyView(
            icon: Icons.error_outline,
            title: 'الفرع غير موجود',
            message: 'قد يكون الفرع قد حُذف أو لم يعد متاحًا.',
          );
        }
        _hydrateFrom(existing);
        return _buildForm(context);
      },
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: <Widget>[
          const _SectionHeader(
            title: 'بيانات الفرع',
            icon: Icons.store_mall_directory_outlined,
          ),
          const SizedBox(height: 10),
          _Card(
            children: <Widget>[
              AppTextField(
                controller: _nameController,
                label: 'اسم الفرع *',
                hint: 'مثال: الفرع الرئيسي',
                enabled: !_isSaving,
                validator: _validateName,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _codeController,
                label: 'الكود',
                hint: 'مثال: CAI-01',
                enabled: !_isSaving,
                validator: _validateCode,
              ),
              const SizedBox(height: 6),
              const _HelperText(
                'كود اختياري لتمييز الفرع داخل الشركة (حروف أو أرقام).',
              ),
            ],
          ),

          const SizedBox(height: 16),

          const _SectionHeader(
            title: 'معلومات الاتصال',
            icon: Icons.contact_phone_outlined,
          ),
          const SizedBox(height: 10),
          _Card(
            children: <Widget>[
              AppTextField(
                controller: _phoneController,
                label: 'رقم الهاتف',
                hint: 'مثال: 0223456789',
                enabled: !_isSaving,
                keyboardType: TextInputType.phone,
                validator: (String? v) =>
                    _validateOptional(v, 30, 'رقم الهاتف'),
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _addressController,
                label: 'العنوان',
                hint: 'العنوان الكامل للفرع',
                enabled: !_isSaving,
                maxLines: 3,
                validator: (String? v) =>
                    _validateOptional(v, 500, 'العنوان'),
              ),
            ],
          ),

          if (_saveFailure != null) ...<Widget>[
            const SizedBox(height: 16),
            _ErrorBanner(message: _failureMessage(_saveFailure!)),
          ],

          const SizedBox(height: 24),

          AppButton(
            label: _isEditMode ? 'حفظ التعديلات' : 'إضافة الفرع',
            icon: Icons.save_outlined,
            expanded: true,
            size: AppButtonSize.large,
            isLoading: _isSaving,
            onPressed: _isSaving ? null : _save,
          ),

          const SizedBox(height: 8),

          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            expanded: true,
            onPressed: _isSaving
                ? null
                : () {
                    if (context.mounted) {
                      context.pop();
                    }
                  },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Localization
  // ---------------------------------------------------------------------------

  static String _errorMessage(Object error) {
    if (error is CompanyException) {
      return _failureMessage(error.type);
    }
    return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
  }

  static String _failureMessage(CompanyFailureType type) {
    switch (type) {
      case CompanyFailureType.network:
        return 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
      case CompanyFailureType.unauthorized:
        return 'ليس لديك صلاحية لإدارة الفروع. '
            'تواصل مع المالك أو المدير.';
      case CompanyFailureType.noCompanies:
        return 'لم يتم العثور على شركات مرتبطة بحسابك.';
      case CompanyFailureType.companyNotAccessible:
        return 'لا يمكن الوصول إلى فروع هذه الشركة.';
      case CompanyFailureType.noBranches:
        return 'لا توجد فروع متاحة.';
      case CompanyFailureType.invalidResponse:
        return 'تحقق من صحة البيانات. '
            'قد يكون اسم الفرع أو الكود مستخدمًا بالفعل.';
      case CompanyFailureType.unknown:
        return 'تعذّر حفظ البيانات. حاول مرة أخرى.';
    }
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
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Card
// ============================================================================

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

// ============================================================================
// Helper text
// ============================================================================

class _HelperText extends StatelessWidget {
  const _HelperText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ============================================================================
// Error banner
// ============================================================================

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
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
