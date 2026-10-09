// lib/features/auth/presentation/widgets/login_form.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_provider.dart';

/// Arabic RTL sign-in form.
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  AuthFailureType? _failureType;

  @override
  void dispose() {
    _emailController.dispose();
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

    final AuthFailureType? failure =
        await ref.read(authProvider.notifier).login(
              email: _emailController.text,
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
              'أدخل بياناتك للوصول إلى حسابك',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            AppTextField(
              controller: _emailController,
              label: 'البريد الإلكتروني',
              hint: 'example@domain.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.alternate_email,
              enabled: !_isSubmitting,
              autofocus: true,
              validator: _validateEmail,
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
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => context.goNamed(AppRouter.signupName),
              child: const Text('ليس لديك حساب؟ أنشئ حسابًا جديدًا'),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    final ValidationError? error = Validators.email(value);
    return error == null ? null : _validationMessage(error);
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
        'البريد الإلكتروني أو كلمة المرور غير صحيحة',
      AuthFailureType.emailNotConfirmed =>
        'لم يتم تأكيد البريد الإلكتروني بعد. يرجى مراجعة بريدك.',
      AuthFailureType.userNotFound =>
        'لا يوجد حساب مرتبط بهذا البريد الإلكتروني.',
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
