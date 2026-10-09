// lib/features/auth/presentation/pages/create_company_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/responsive/responsive_helper.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../companies/domain/repositories/company_repository.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';

/// Phase T-3: post-OAuth onboarding screen.
///
/// Shown when an authenticated user has no company yet. This happens for
/// users who signed in with Google (Supabase Auth does not let the client
/// inject custom `company_name` metadata through the OAuth flow), so the
/// company must be created from the app after the session is established.
///
/// The RPC `create_my_company` performs the whole bootstrap (company +
/// owner membership + default branch) transactionally and enforces the
/// "one owned company per user" invariant.
class CreateCompanyPage extends ConsumerStatefulWidget {
  const CreateCompanyPage({super.key});

  @override
  ConsumerState<CreateCompanyPage> createState() => _CreateCompanyPageState();
}

class _CreateCompanyPageState extends ConsumerState<CreateCompanyPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _isSubmitting = true);

    try {
      await ref
          .read(companyRepositoryProvider)
          .createMyCompany(name: _nameController.text.trim());

      // Reload the company context so the freshly created company becomes
      // the active one and the rest of the app can proceed normally.
      await ref.read(companyContextProvider.notifier).refresh();

      if (!mounted) return;
      context.goNamed(AppRouter.homeName);
    } on CompanyException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = _messageFor(error.type);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
      });
    }
  }

  static String _messageFor(CompanyFailureType type) => switch (type) {
        CompanyFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.',
        CompanyFailureType.unauthorized =>
          'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
        CompanyFailureType.noCompanies => 'لا توجد شركات.',
        CompanyFailureType.companyNotAccessible =>
          'لا يمكن الوصول إلى هذه الشركة.',
        CompanyFailureType.noBranches => 'لا توجد فروع.',
        CompanyFailureType.invalidResponse =>
          'قد يكون لديك شركة بالفعل. جرّب العودة للرئيسية.',
        CompanyFailureType.unknown =>
          'تعذّر إنشاء الشركة. حاول مرة أخرى.',
      };

  String? _validateName(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'الرجاء إدخال اسم الشركة';
    }
    if (v.length > 200) {
      return 'اسم الشركة طويل جدًا (الحد الأقصى 200 حرف)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

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
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
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
                                    Icons.apartment_outlined,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'حسابي',
                                style: theme.textTheme.headlineMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'أنشئ شركتك',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'خطوة واحدة تفصلك عن البدء. سنُنشئ لك فرعًا '
                            'رئيسيًا افتراضيًا وتجربة مجانية 7 أيام.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          AppTextField(
                            controller: _nameController,
                            label: 'اسم الشركة',
                            hint: 'مؤسسة النور للتجارة',
                            enabled: !_isSubmitting,
                            autofocus: true,
                            textInputAction: TextInputAction.done,
                            validator: _validateName,
                            onSubmitted: (_) =>
                                _isSubmitting ? null : _submit(),
                          ),
                          if (_errorMessage != null) ...<Widget>[
                            const SizedBox(height: 12),
                            _ErrorBanner(message: _errorMessage!),
                          ],
                          const SizedBox(height: 24),
                          AppButton(
                            label: 'إنشاء الشركة والبدء',
                            icon: Icons.rocket_launch_outlined,
                            expanded: true,
                            size: AppButtonSize.large,
                            isLoading: _isSubmitting,
                            onPressed: _isSubmitting ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
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
