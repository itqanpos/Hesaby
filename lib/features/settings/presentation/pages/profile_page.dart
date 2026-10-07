// lib/features/settings/presentation/pages/profile_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_profile_repository.dart';
import '../providers/user_profile_providers.dart';

/// Personal profile page — user's display name, phone, email, and password.
///
/// The email is read-only (managed by Supabase Auth). Changing the password
/// opens a bottom sheet and calls `AuthNotifier.changePassword`.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;

  bool _initialized = false;
  bool _isSaving = false;
  UserProfileFailureType? _saveFailure;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _hydrate(UserProfile profile) {
    if (_initialized) return;
    _initialized = true;
    _fullNameController.text = profile.fullName ?? '';
    _phoneController.text = profile.phone ?? '';
  }

  // ---------------------------------------------------------------------------
  // Save (profile)
  // ---------------------------------------------------------------------------

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();

    if (_saveFailure != null) {
      setState(() => _saveFailure = null);
    }

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _isSaving = true);

    try {
      await ref.read(userProfileProvider.notifier).updateProfile(
            fullName: _emptyToNull(_fullNameController.text),
            phone: _emptyToNull(_phoneController.text),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم حفظ الملف الشخصي.')),
        );
    } on UserProfileException catch (error) {
      if (!mounted) return;
      setState(() => _saveFailure = error.type);
    } on Object {
      if (!mounted) return;
      setState(() => _saveFailure = UserProfileFailureType.unknown);
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
  // Change password
  // ---------------------------------------------------------------------------

  Future<void> _openChangePasswordSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) =>
          const _ChangePasswordSheet(),
    );
  }

  // ---------------------------------------------------------------------------
  // Validators
  // ---------------------------------------------------------------------------

  String? _validateFullName(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null; // Optional.
    if (trimmed.length > 200) {
      return 'الاسم طويل جدًا (الحد الأقصى 200 حرف)';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 30) {
      return 'رقم الهاتف طويل جدًا (الحد الأقصى 30 حرف)';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<UserProfile?> profileAsync =
        ref.watch(userProfileProvider);
    final String email =
        ref.watch(authProvider).session?.email ?? '—';

    return AppShell(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: profileAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الملف الشخصي',
          message: _errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: () => ref.read(userProfileProvider.notifier).refresh(),
        ),
        data: (UserProfile? profile) {
          if (profile == null) {
            return const AppLoader();
          }
          _hydrate(profile);
          return _buildForm(email);
        },
      ),
    );
  }

  Widget _buildForm(String email) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: <Widget>[
          const _SectionHeader(
            title: 'المعلومات الشخصية',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 10),
          _Card(
            children: <Widget>[
              AppTextField(
                controller: _fullNameController,
                label: 'الاسم الكامل',
                hint: 'الاسم الذي يظهر في التطبيق',
                enabled: !_isSaving,
                validator: _validateFullName,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _phoneController,
                label: 'رقم الهاتف',
                hint: 'مثال: 01012345678',
                enabled: !_isSaving,
                keyboardType: TextInputType.phone,
                validator: _validatePhone,
              ),
            ],
          ),

          if (_saveFailure != null) ...<Widget>[
            const SizedBox(height: 16),
            _ErrorBanner(message: _profileFailureMessage(_saveFailure!)),
          ],

          const SizedBox(height: 16),

          AppButton(
            label: 'حفظ التعديلات',
            icon: Icons.save_outlined,
            expanded: true,
            size: AppButtonSize.large,
            isLoading: _isSaving,
            onPressed: _isSaving ? null : _saveProfile,
          ),

          const SizedBox(height: 24),

          const _SectionHeader(
            title: 'البريد الإلكتروني',
            icon: Icons.mail_outline,
          ),
          const SizedBox(height: 10),
          _Card(
            children: <Widget>[
              _ReadOnlyRow(
                icon: Icons.mail_outline,
                label: 'البريد الإلكتروني',
                value: email,
              ),
              const SizedBox(height: 8),
              const _HelperText(
                'لا يمكن تغيير البريد الإلكتروني من التطبيق حاليًا. '
                'تواصل مع الدعم إن لزم الأمر.',
              ),
            ],
          ),

          const SizedBox(height: 24),

          const _SectionHeader(
            title: 'الأمان',
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: 10),
          _Card(
            children: <Widget>[
              AppButton(
                label: 'تغيير كلمة المرور',
                icon: Icons.lock_reset_outlined,
                variant: AppButtonVariant.secondary,
                expanded: true,
                onPressed: _openChangePasswordSheet,
              ),
              const SizedBox(height: 8),
              const _HelperText(
                'يُنصح باستخدام كلمة مرور لا تقل عن 8 أحرف، '
                'تجمع بين حروف كبيرة وصغيرة وأرقام.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Localization
  // ---------------------------------------------------------------------------

  static String _errorMessage(Object error) {
    if (error is UserProfileException) {
      return _profileFailureMessage(error.type);
    }
    return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
  }

  static String _profileFailureMessage(UserProfileFailureType type) {
    switch (type) {
      case UserProfileFailureType.network:
        return 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
      case UserProfileFailureType.unauthorized:
        return 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مجددًا.';
      case UserProfileFailureType.notFound:
        return 'لم يتم العثور على ملفك الشخصي.';
      case UserProfileFailureType.invalidInput:
        return 'تحقق من صحة البيانات المُدخلة.';
      case UserProfileFailureType.invalidResponse:
        return 'تعذّر قراءة البيانات من الخادم.';
      case UserProfileFailureType.unknown:
        return 'تعذّر حفظ البيانات. حاول مرة أخرى.';
    }
  }
}

// ============================================================================
// Change password sheet
// ============================================================================

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState
    extends ConsumerState<_ChangePasswordSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isSaving = false;
  AuthFailureType? _failure;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_failure != null) {
      setState(() => _failure = null);
    }

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _isSaving = true);

    final AuthFailureType? failure =
        await ref.read(authProvider.notifier).changePassword(
              newPassword: _passwordController.text,
            );

    if (!mounted) return;

    if (failure == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم تحديث كلمة المرور.')),
        );
      return;
    }

    setState(() {
      _isSaving = false;
      _failure = failure;
    });
  }

  String? _validatePassword(String? value) {
    final String trimmed = value ?? '';
    if (trimmed.isEmpty) return 'الرجاء إدخال كلمة المرور الجديدة';
    if (trimmed.length < 8) {
      return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) {
      return 'الرجاء تأكيد كلمة المرور';
    }
    if (value != _passwordController.text) {
      return 'كلمتا المرور غير متطابقتين';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'تغيير كلمة المرور',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),

                AppTextField(
                  controller: _passwordController,
                  label: 'كلمة المرور الجديدة',
                  obscureText: true,
                  enabled: !_isSaving,
                  validator: _validatePassword,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _confirmController,
                  label: 'تأكيد كلمة المرور',
                  obscureText: true,
                  enabled: !_isSaving,
                  validator: _validateConfirm,
                ),

                if (_failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _ErrorBanner(message: _authFailureMessage(_failure!)),
                ],

                const SizedBox(height: 20),

                AppButton(
                  label: 'تحديث كلمة المرور',
                  icon: Icons.check_circle_outline,
                  expanded: true,
                  size: AppButtonSize.large,
                  isLoading: _isSaving,
                  onPressed: _isSaving ? null : _submit,
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'إلغاء',
                  variant: AppButtonVariant.text,
                  expanded: true,
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 4),
                Text(
                  'لن يتم تسجيل خروجك من الجلسة الحالية.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
// Read-only row
// ============================================================================

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Icon(icon, color: scheme.onSurfaceVariant, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
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

// ============================================================================
// Auth failure localization
// ============================================================================

String _authFailureMessage(AuthFailureType type) {
  switch (type) {
    case AuthFailureType.invalidCredentials:
      return 'كلمة المرور الحالية غير صحيحة أو انتهت الجلسة. '
          'حاول تسجيل الدخول مجددًا.';
    case AuthFailureType.emailNotConfirmed:
      return 'البريد الإلكتروني غير مؤكد.';
    case AuthFailureType.userNotFound:
      return 'تعذّر العثور على حسابك.';
    case AuthFailureType.tooManyRequests:
      return 'محاولات كثيرة. يرجى المحاولة بعد قليل.';
    case AuthFailureType.weakPassword:
      return 'كلمة المرور ضعيفة. استخدم 8 أحرف على الأقل مع أرقام وحروف.';
    case AuthFailureType.network:
      return 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
    case AuthFailureType.unknown:
      return 'تعذّر تغيير كلمة المرور. حاول مرة أخرى.';
  }
}
