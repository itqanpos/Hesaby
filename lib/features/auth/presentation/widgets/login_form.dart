// lib/features/auth/presentation/widgets/login_form.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_provider.dart';

/// Arabic RTL sign-in form.
///
/// The identity field accepts **either** an email address **or** an
/// employee login code (e.g. `ahmed01`). When a bare code is entered, the
/// form appends `@hesaby.local` before calling the auth notifier — that
/// reserved domain is what `create_employee_user` uses under the hood.
///
/// **Self-signup is disabled.** Account creation is provisioned by the
/// platform admin from the admin dashboard. Users without an account are
/// instructed to contact the administrator instead of being routed to a
/// public signup page.
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identityController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  AuthFailureType? _failureType;

  @override
  void dispose() {
    _identityController.dispose();
    _passwordController.dispose();
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

    // Normalize: bare code → code@hesaby.local. Anything containing "@"
    // is treated as an email.
    final String raw = _identityController.text.trim();
    final String email = raw.contains('@')
        ? raw
        : '${raw.toLowerCase()}@hesaby.local';

    final AuthFailureType? failure =
        await ref.read(authProvider.notifier).login(
              email: email,
              password: _passwordController.text,
            );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
      _failureType = failure;
    });
  }

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthFailureType? failure = _failureType;

    return AutofillGroup(
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'تسجيل الدخول',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'أدخل بريدك الإلكتروني أو كود الدخول',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            AppTextField(
              controller: _identityController,
              label: 'البريد أو كود الدخول',
              hint: 'example@domain.com · ahmed01',
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.alternate_email,
              enabled: !_isSubmitting,
              autofocus: true,
              validator: _validateIdentity,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _passwordController,
              label: 'كلمة المرور',
              hint: '••••••••',
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.lock_outline,
              suffixIcon: IconButton(
                onPressed:
                    _isSubmitting ? null : _togglePasswordVisibility,
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscurePassword
                    ? 'إظهار كلمة المرور'
                    : 'إخفاء كلمة المرور',
              ),
              enabled: !_isSubmitting,
              validator: _validatePassword,
              onSubmitted: (_) => _isSubmitting ? null : _submit(),
            ),
            if (failure != null) ...<Widget>[
              const SizedBox(height: 16),
              _FailureBanner(message: _failureMessage(failure)),
            ],
            const SizedBox(height: 24),
            AppButton(
              label: 'تسجيل الدخول',
              icon: Icons.login,
              expanded: true,
              size: AppButtonSize.large,
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submit,
            ),
            const SizedBox(height: 16),
            // ⬇️ رابط إنشاء الحساب أُزيل — التسجيل الآن عبر إدارة المنصة فقط.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'لإنشاء حساب جديد، تواصل مع إدارة المنصة.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Validates the identity field — accepts an email or a login code.
  String? _validateIdentity(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'هذا الحقل مطلوب';
    }

    // Contains "@"? Treat as email — reuse the shared validator.
    if (v.contains('@')) {
      final ValidationError? error = Validators.email(v);
      return error == null ? null : _validationMessage(error);
    }

    // Bare code — same format as create_employee_user expects.
    final RegExp codePattern = RegExp(r'^[a-zA-Z0-9_-]{3,30}$');
    if (!codePattern.hasMatch(v)) {
      return 'كود الدخول: 3-30 حرف (a-z، 0-9، _، -)';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final ValidationError? error = Validators.required(value);
    return error == null ? null : _validationMessage(error);
  }
}

String _validationMessage(ValidationError error) => switch (error) {
      ValidationError.required => 'هذا الحقل مطلوب',
      ValidationError.invalidEmail => 'صيغة البريد الإلكتروني غير صحيحة',
      ValidationError.invalidPhone => 'صيغة رقم الهاتف غير صحيحة',
      ValidationError.tooShort => 'القيمة قصيرة جدًا',
      ValidationError.tooLong => 'القيمة طويلة جدًا',
      ValidationError.invalidNumber => 'يجب إدخال رقم صحيح',
      ValidationError.mustBePositive => 'يجب أن تكون القيمة موجبة',
    };

String _failureMessage(AuthFailureType type) => switch (type) {
      AuthFailureType.invalidCredentials =>
        'البيانات غير صحيحة. تحقق من الكود أو البريد وكلمة السر.',
      AuthFailureType.emailNotConfirmed =>
        'الحساب غير مؤكد. تواصل مع مدير الشركة.',
      AuthFailureType.userNotFound =>
        'لا يوجد حساب مرتبط بهذا الكود أو البريد.',
      AuthFailureType.tooManyRequests =>
        'تمت محاولات كثيرة. يرجى المحاولة بعد قليل.',
      AuthFailureType.weakPassword =>
        'كلمة المرور ضعيفة. يرجى استخدام كلمة مرور أقوى.',
      AuthFailureType.emailAlreadyInUse =>
        'هذا البريد الإلكتروني مُستخدم بالفعل. جرّب تسجيل الدخول.',
      AuthFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      AuthFailureType.unknown =>
        'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.',
    };

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
