// lib/features/companies/presentation/pages/company_profile_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/company.dart';
import '../../domain/repositories/company_repository.dart';
import '../providers/company_context_provider.dart';
import '../providers/company_context_state.dart';

/// Company profile page — basic identity, contact info and regional
/// settings of the currently selected company.
///
/// The save action calls `CompanyContextNotifier.updateCurrentCompany`,
/// which is gated server-side by RLS to the `owner` and `admin` roles.
/// Callers without those roles receive a translated "unauthorized" message
/// and the form remains open, so the user can simply navigate back.
class CompanyProfilePage extends ConsumerStatefulWidget {
  const CompanyProfilePage({super.key});

  @override
  ConsumerState<CompanyProfilePage> createState() =>
      _CompanyProfilePageState();
}

class _CompanyProfilePageState extends ConsumerState<CompanyProfilePage> {
  /// Curated list of ISO-4217 currencies supported by the app.
  static const List<String> _currencies = <String>[
    'EGP',
    'SAR',
    'AED',
    'KWD',
    'QAR',
    'BHD',
    'OMR',
    'JOD',
    'USD',
    'EUR',
  ];

  /// Curated list of IANA timezones relevant to the MENA market.
  static const List<String> _timezones = <String>[
    'Africa/Cairo',
    'Africa/Casablanca',
    'Africa/Tunis',
    'Africa/Algiers',
    'Africa/Khartoum',
    'Asia/Riyadh',
    'Asia/Dubai',
    'Asia/Kuwait',
    'Asia/Qatar',
    'Asia/Bahrain',
    'Asia/Muscat',
    'Asia/Amman',
    'Asia/Beirut',
    'Asia/Baghdad',
    'UTC',
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _legalNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;

  String _currency = 'EGP';
  String _timezone = 'Africa/Cairo';

  bool _initialized = false;
  bool _isSaving = false;
  CompanyFailureType? _saveFailure;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _legalNameController = TextEditingController();
    _phoneController = TextEditingController();
    _emailController = TextEditingController();
    _addressController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _legalNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Hydration
  // ---------------------------------------------------------------------------

  void _hydrate(Company company) {
    if (_initialized) return;
    _initialized = true;

    _nameController.text = company.name;
    _legalNameController.text = company.legalName ?? '';
    _phoneController.text = company.phone ?? '';
    _emailController.text = company.email ?? '';
    _addressController.text = company.address ?? '';

    _currency = _currencies.contains(company.currency)
        ? company.currency
        : _currencies.first;
    _timezone = _timezones.contains(company.timezone)
        ? company.timezone
        : _timezones.first;
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

    try {
      await ref.read(companyContextProvider.notifier).updateCurrentCompany(
            name: _nameController.text.trim(),
            currency: _currency,
            timezone: _timezone,
            legalName: _emptyToNull(_legalNameController.text),
            phone: _emptyToNull(_phoneController.text),
            email: _emptyToNull(_emailController.text),
            address: _emptyToNull(_addressController.text),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم حفظ بيانات الشركة.')),
        );
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
      return 'الرجاء إدخال اسم الشركة';
    }
    if (trimmed.length > 200) {
      return 'الاسم طويل جدًا (الحد الأقصى 200 حرف)';
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

  String? _validateEmail(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 200) {
      return 'البريد الإلكتروني طويل جدًا';
    }
    // Simple client-side check; the database enforces the real format.
    final RegExp pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!pattern.hasMatch(trimmed)) {
      return 'صيغة البريد الإلكتروني غير صحيحة';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final CompanyContextState contextState = ref.watch(companyContextProvider);
    final Company? company = contextState.currentCompany;

    return AppShell(
      appBar: AppBar(title: const Text('بيانات الشركة')),
      body: _buildBody(contextState, company),
    );
  }

  Widget _buildBody(
    CompanyContextState contextState,
    Company? company,
  ) {
    if (company != null) {
      _hydrate(company);
      return _buildForm();
    }

    if (contextState.isLoadingCompanies) {
      return const AppLoader();
    }

    if (contextState.companiesFailure != null) {
      return AppErrorView(
        title: 'تعذّر تحميل بيانات الشركة',
        message: _failureMessage(contextState.companiesFailure!),
        retryLabel: 'إعادة المحاولة',
        onRetry: () => ref.read(companyContextProvider.notifier).refresh(),
      );
    }

    return const AppEmptyView(
      icon: Icons.business_outlined,
      title: 'لا توجد شركة محددة',
      message: 'اختر شركة من الصفحة الرئيسية ثم عد إلى هنا.',
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: <Widget>[
          // ---- Basic data ----
          const _SectionHeader(
            title: 'البيانات الأساسية',
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 10),
          _Card(
            children: <Widget>[
              AppTextField(
                controller: _nameController,
                label: 'اسم الشركة *',
                hint: 'مثال: مؤسسة النور',
                enabled: !_isSaving,
                validator: _validateName,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _legalNameController,
                label: 'الاسم القانوني',
                hint: 'الاسم كما يظهر في الأوراق الرسمية',
                enabled: !_isSaving,
                validator: (String? v) =>
                    _validateOptional(v, 300, 'الاسم القانوني'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ---- Contact ----
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
                controller: _emailController,
                label: 'البريد الإلكتروني',
                hint: 'example@company.com',
                enabled: !_isSaving,
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _addressController,
                label: 'العنوان',
                hint: 'العنوان الكامل',
                enabled: !_isSaving,
                maxLines: 3,
                validator: (String? v) =>
                    _validateOptional(v, 500, 'العنوان'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ---- Regional ----
          const _SectionHeader(
            title: 'الإعدادات الإقليمية',
            icon: Icons.public_outlined,
          ),
          const SizedBox(height: 10),
          _Card(
            children: <Widget>[
              _DropdownField<String>(
                label: 'العملة',
                value: _currency,
                items: _currencies,
                enabled: !_isSaving,
                labelBuilder: (String value) => value,
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _currency = value);
                  }
                },
              ),
              const SizedBox(height: 14),
              _DropdownField<String>(
                label: 'المنطقة الزمنية',
                value: _timezone,
                items: _timezones,
                enabled: !_isSaving,
                labelBuilder: (String value) => value,
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _timezone = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              const _HelperText(
                'تُستخدم العملة في الفواتير والتقارير، والمنطقة الزمنية في تواريخ الفواتير.',
              ),
            ],
          ),

          if (_saveFailure != null) ...<Widget>[
            const SizedBox(height: 16),
            _ErrorBanner(message: _failureMessage(_saveFailure!)),
          ],

          const SizedBox(height: 24),

          AppButton(
            label: 'حفظ التعديلات',
            icon: Icons.save_outlined,
            expanded: true,
            size: AppButtonSize.large,
            isLoading: _isSaving,
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Localization
  // ---------------------------------------------------------------------------

  static String _failureMessage(CompanyFailureType type) {
    switch (type) {
      case CompanyFailureType.network:
        return 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
      case CompanyFailureType.unauthorized:
        return 'ليس لديك صلاحية لتعديل بيانات الشركة. '
            'تواصل مع المالك أو المدير.';
      case CompanyFailureType.noCompanies:
        return 'لم يتم العثور على شركات مرتبطة بحسابك.';
      case CompanyFailureType.companyNotAccessible:
        return 'لا يمكن الوصول إلى هذه الشركة.';
      case CompanyFailureType.noBranches:
        return 'لا توجد فروع متاحة لهذه الشركة.';
      case CompanyFailureType.invalidResponse:
        return 'تعذّر قراءة البيانات من الخادم.';
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
// Dropdown field (themed, no deprecation)
// ============================================================================

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.enabled,
    required this.labelBuilder,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final bool enabled;
  final String Function(T value) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: <DropdownMenuItem<T>>[
            for (final T item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(
                  labelBuilder(item),
                  style: theme.textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled ? onChanged : null,
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
