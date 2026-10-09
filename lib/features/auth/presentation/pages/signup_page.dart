// lib/features/auth/presentation/pages/signup_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/responsive/responsive_helper.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_provider.dart';
import '../widgets/google_sign_in_button.dart';

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _companyController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  AuthFailureType? _failure;
  bool _confirmationSent = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _companyController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_failure != null) {
      setState(() => _failure = null);
    }

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      return;
    }

    setState(() => _isSubmitting = true);

    final String name = _nameController.text.trim();
    final String company = _companyController.text.trim();

    final Object? result = await ref.read(authProvider.notifier).signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: name.isEmpty ? null : name,
          companyName: company.isEmpty ? null : company,
        );

    if (!mounted) {
      return;
    }

    if (result == null) {
      context.goNamed(AppRouter.homeName);
      return;
    }

    if (result == AuthSignUpResult.needsEmailConfirmation) {
      setState(() {
        _isSubmitting = false;
        _confirmationSent = true;
      });
      return;
    }

    setState(() {
      _isSubmitting = false;
      _failure =
          result is AuthFailureType ? result : AuthFailureType.unknown;
    });
  }

  String? _validateName(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'الرجاء إدخال اسمك';
    }
    if (v.length > 200) {
      return 'الاسم طويل جدًا';
    }
    return null;
  }

  String? _validateCompany(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'الرجاء إدخال اسم الشركة';
    }
    if (v.length > 200) {
      return 'اسم الشركة طويل جدًا';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'الرجاء إدخال البريد الإلكتروني';
    }
    final RegExp pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!pattern.hasMatch(v)) {
      return 'صيغة البريد غير صحيحة';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final String v = value ?? '';
    if (v.isEmpty) {
      return 'الرجاء إدخال كلمة المرور';
    }
    if (v.length < 6) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AppShell(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : ResponsiveHelper.contentMaxWidth;
          final double formMaxWidth =
              availableWidth < 480 ? availableWidth : 480;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: formMaxWidth),
                child: _SignUpCard(
                  theme: theme,
                  child: _confirmationSent
                      ? _ConfirmationSentBody(
                          email: _emailController.text.trim(),
                        )
                      : _buildForm(theme),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'إنشاء حساب جديد',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'أنشئ حسابك وشركتك في خطوة واحدة.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _nameController,
            label: 'الاسم الكامل',
            hint: 'أحمد محمد',
            enabled: !_isSubmitting,
            autofocus: true,
            textInputAction: TextInputAction.next,
            validator: _validateName,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _companyController,
            label: 'اسم الشركة',
            hint: 'مؤسسة النور للتجارة',
            enabled: !_isSubmitting,
            textInputAction: TextInputAction.next,
            validator: _validateCompany,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _emailController,
            label: 'البريد الإلكتروني',
            hint: 'example@domain.com',
            enabled: !_isSubmitting,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: _validateEmail,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _passwordController,
            label: 'كلمة المرور',
            hint: '6 أحرف على الأقل',
            enabled: !_isSubmitting,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            suffixIcon: IconButton(
              onPressed: _isSubmitting
                  ? null
                  : () =>
                      setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            validator: _validatePassword,
            onSubmitted: (_) => _isSubmitting ? null : _submit(),
          ),
          if (_failure != null) ...<Widget>[
            const SizedBox(height: 12),
            _ErrorBanner(message: _failureMessage(_failure!)),
          ],
          const SizedBox(height: 24),
          AppButton(
            label: 'إنشاء الحساب',
            icon: Icons.person_add_alt,
            expanded: true,
            size: AppButtonSize.large,
            isLoading: _isSubmitting,
            onPressed: _isSubmitting ? null : _submit,
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'أو',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 12),
          const GoogleSignInButton(),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => context.goNamed(AppRouter.loginName),
            child: const Text('لديك حساب بالفعل؟ سجّل الدخول'),
          ),
        ],
      ),
    );
  }

  static String _failureMessage(AuthFailureType type) {
    switch (type) {
      case AuthFailureType.invalidCredentials:
        return 'البريد أو كلمة المرور غير صحيحة.';
      case AuthFailureType.emailNotConfirmed:
        return 'البريد الإلكتروني غير مؤكد.';
      case AuthFailureType.userNotFound:
        return 'الحساب غير موجود.';
      case AuthFailureType.tooManyRequests:
        return 'محاولات كثيرة. يرجى المحاولة بعد قليل.';
      case AuthFailureType.weakPassword:
        return 'كلمة المرور ضعيفة. استخدم 6 أحرف على الأقل.';
      case AuthFailureType.emailAlreadyInUse:
        return 'هذا البريد مُستخدم بالفعل. جرّب تسجيل الدخول.';
      case AuthFailureType.network:
        return 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
      case AuthFailureType.unknown:
        return 'تعذّر إنشاء الحساب. حاول مرة أخرى.';
    }
  }
}

class _SignUpCard extends StatelessWidget {
  const _SignUpCard({required this.theme, required this.child});

  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.receipt_long_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'حسابي',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}

class _ConfirmationSentBody extends StatelessWidget {
  const _ConfirmationSentBody({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(
          Icons.mark_email_unread_outlined,
          size: 64,
          color: scheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          'تم إنشاء حسابك!',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'أرسلنا رابط تأكيد إلى:\n$email\n\n'
          'افتح البريد واضغط الرابط لتفعيل حسابك.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => context.goNamed(AppRouter.loginName),
          child: const Text('العودة لتسجيل الدخول'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: scheme.onErrorContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
