// lib/features/auth/presentation/pages/signup_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';

/// **Registration is disabled.**
///
/// This page is retained only as a safety net: if a user somehow reaches
/// `/signup` before the router redirect kicks in (deep link, stale bookmark,
/// race during auth state change), they see a clear "registration closed"
/// message instead of a sign-up form.
///
/// Account creation is provisioned by the platform administrator from the
/// admin dashboard. Customers receive credentials from the administrator
/// and simply sign in via [LoginPage].
class SignUpPage extends StatelessWidget {
  const SignUpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AppShell(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.lock_outline,
                          color: scheme.onPrimaryContainer,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'التسجيل مغلق',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'لا يمكن إنشاء حساب جديد مباشرة من التطبيق. '
                      'يتم إنشاء جميع الحسابات من قبل إدارة المنصة لضمان '
                      'التحكم في الوصول ومنع الحسابات المكررة.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'كيف أحصل على حساب؟',
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'تواصل مع إدارة المنصة عبر واتساب أو البريد '
                              'الإلكتروني، وسيتم إنشاء حسابك وإرسال بيانات '
                              'الدخول إليك.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      label: 'العودة لتسجيل الدخول',
                      icon: Icons.arrow_forward,
                      expanded: true,
                      onPressed: () =>
                          context.goNamed(AppRouter.loginName),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
