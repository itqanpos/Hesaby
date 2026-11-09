// lib/features/auth/presentation/pages/signup_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';

/// صفحة إنشاء حساب جديد.
///
/// تستخدم Supabase Auth مباشرة. عند النجاح:
/// - إن كانت الجلسة جاهزة (تأكيد البريد معطّل) → ينتقل للرئيسية مباشرة.
/// - إن كان التأكيد مطلوباً → يعود لتسجيل الدخول مع رسالة توضيحية.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_error != null) setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        data: <String, dynamic>{
          'full_name': _nameCtrl.text.trim(),
        },
      );

      if (!mounted) return;

      if (response.session != null) {
        // تأكيد البريد معطّل — المستخدم مسجّل الدخول فوراً
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('تم إنشاء الحساب بنجاح. مرحباً بك!'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        context.goNamed(AppRouter.homeName);
      } else {
        // تأكيد البريد مطلوب
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'تم إنشاء الحساب. يرجى تأكيد بريدك الإلكتروني ثم تسجيل الدخول.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        context.goNamed(AppRouter.loginName);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapAuthError(e);
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
        _loading = false;
      });
    }
  }

  String _mapAuthError(AuthException e) {
    final String msg = e.message.toLowerCase();
    if (msg.contains('already registered') ||
        msg.contains('user already') ||
        msg.contains('already exists')) {
      return 'هذا البريد مسجل بالفعل. جرّب تسجيل الدخول.';
    }
    if (msg.contains('password') &&
        (msg.contains('weak') || msg.contains('short'))) {
      return 'كلمة المرور ضعيفة. استخدم 8 أحرف على الأقل.';
    }
    if (msg.contains('invalid email') || msg.contains('email address')) {
      return 'البريد الإلكتروني غير صحيح.';
    }
    if (msg.contains('rate limit')) {
      return 'محاولات كثيرة. يرجى الانتظار دقيقة والمحاولة مجدداً.';
    }
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppShell(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              scheme.primaryContainer.withValues(alpha: 0.15),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                vertical: 24,
                horizontal: 16,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // ── Header ──
                          Center(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                Icons.person_add_alt_1_outlined,
                                color: scheme.onPrimaryContainer,
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'إنشاء حساب جديد',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ابدأ بإدارة أعمالك من مكان واحد',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── الاسم ──
                          TextFormField(
                            controller: _nameCtrl,
                            enabled: !_loading,
                            textInputAction: TextInputAction.next,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'الاسم الكامل',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (String? v) {
                              final String t = (v ?? '').trim();
                              if (t.isEmpty) return 'الرجاء إدخال الاسم';
                              if (t.length < 2) return 'الاسم قصير جداً';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // ── البريد ──
                          TextFormField(
                            controller: _emailCtrl,
                            enabled: !_loading,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'البريد الإلكتروني',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (String? v) {
                              final String t = (v ?? '').trim();
                              if (t.isEmpty) return 'الرجاء إدخال البريد';
                              final RegExp re = RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              );
                              if (!re.hasMatch(t)) return 'بريد غير صحيح';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // ── كلمة المرور ──
                          TextFormField(
                            controller: _passwordCtrl,
                            enabled: !_loading,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.next,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: _loading
                                    ? null
                                    : () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (String? v) {
                              final String t = v ?? '';
                              if (t.length < 8) {
                                return 'كلمة المرور 8 أحرف على الأقل';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // ── تأكيد كلمة المرور ──
                          TextFormField(
                            controller: _confirmCtrl,
                            enabled: !_loading,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            textDirection: TextDirection.ltr,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: 'تأكيد كلمة المرور',
                              prefixIcon: Icon(Icons.lock_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (String? v) {
                              if (v != _passwordCtrl.text) {
                                return 'كلمتا المرور غير متطابقتين';
                              }
                              return null;
                            },
                          ),

                          // ── خطأ ──
                          if (_error != null) ...<Widget>[
                            const SizedBox(height: 14),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Icon(
                                      Icons.error_outline,
                                      color: scheme.onErrorContainer,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: scheme.onErrorContainer,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 22),

                          // ── زر الإرسال ──
                          AppButton(
                            label: 'إنشاء الحساب',
                            icon: Icons.check_circle_outline,
                            expanded: true,
                            size: AppButtonSize.large,
                            isLoading: _loading,
                            onPressed: _loading ? null : _submit,
                          ),

                          const SizedBox(height: 14),

                          // ── رابط تسجيل الدخول ──
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              Text(
                                'لديك حساب بالفعل؟',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => context.goNamed(
                                          AppRouter.loginName,
                                        ),
                                child: const Text(
                                  'تسجيل الدخول',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
