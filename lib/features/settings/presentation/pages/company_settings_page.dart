// lib/features/settings/presentation/pages/company_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../domain/entities/company_settings.dart';
import '../../domain/repositories/company_settings_repository.dart';
import '../providers/company_settings_providers.dart';

/// Company settings page — business defaults per company.
///
/// Loads the current row and shows it in a form. On save, a partial update
/// is sent (only the fields that were changed are considered, though the
/// repository tolerates a full payload).
///
/// Access is restricted by RLS to owner / admin / manager; a cashier who
/// somehow reaches this page will see an "unauthorized" error instead of a
/// broken form.
class CompanySettingsPage extends ConsumerStatefulWidget {
  const CompanySettingsPage({super.key});

  @override
  ConsumerState<CompanySettingsPage> createState() =>
      _CompanySettingsPageState();
}

class _CompanySettingsPageState extends ConsumerState<CompanySettingsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _taxRateController;
  late final TextEditingController _maxDiscountController;
  late final TextEditingController _footerController;

  bool _allowSaleWithoutStock = false;
  bool _allowCreditSale = true;

  bool _initialized = false;
  bool _isSaving = false;
  CompanySettingsFailureType? _saveFailure;

  @override
  void initState() {
    super.initState();
    _taxRateController = TextEditingController();
    _maxDiscountController = TextEditingController();
    _footerController = TextEditingController();
  }

  @override
  void dispose() {
    _taxRateController.dispose();
    _maxDiscountController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Hydration from loaded settings
  // ---------------------------------------------------------------------------

  void _hydrate(CompanySettings settings) {
    if (_initialized) return;
    _initialized = true;
    _taxRateController.text = _formatNumber(settings.defaultTaxRate);
    _maxDiscountController.text = _formatNumber(settings.maxDiscountPercent);
    _footerController.text = settings.receiptFooter;
    _allowSaleWithoutStock = settings.allowSaleWithoutStock;
    _allowCreditSale = settings.allowCreditSale;
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
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

    final double taxRate =
        double.tryParse(_taxRateController.text.trim()) ?? 0;
    final double maxDiscount =
        double.tryParse(_maxDiscountController.text.trim()) ?? 0;
    final String footer = _footerController.text.trim();

    setState(() => _isSaving = true);

    try {
      await ref.read(companySettingsProvider.notifier).updateSettings(
            defaultTaxRate: taxRate,
            maxDiscountPercent: maxDiscount,
            allowSaleWithoutStock: _allowSaleWithoutStock,
            allowCreditSale: _allowCreditSale,
            receiptFooter: footer,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم حفظ الإعدادات.')),
        );
    } on CompanySettingsException catch (error) {
      if (!mounted) return;
      setState(() => _saveFailure = error.type);
    } on Object {
      if (!mounted) return;
      setState(() => _saveFailure = CompanySettingsFailureType.unknown);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CompanySettings> settingsAsync =
        ref.watch(companySettingsProvider);

    return AppShell(
      appBar: AppBar(title: const Text('إعدادات الشركة')),
      body: settingsAsync.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => AppErrorView(
          title: 'تعذّر تحميل الإعدادات',
          message: _errorMessage(error),
          retryLabel: 'إعادة المحاولة',
          onRetry: () =>
              ref.read(companySettingsProvider.notifier).refresh(),
        ),
        data: (CompanySettings settings) {
          _hydrate(settings);

          return Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              children: <Widget>[
                // ---- Sales rules ----
                const _SectionHeader(
                  title: 'البيع والضرائب',
                  icon: Icons.receipt_long_outlined,
                ),
                const SizedBox(height: 10),
                _Card(
                  children: <Widget>[
                    AppTextField(
                      controller: _taxRateController,
                      label: 'نسبة الضريبة الافتراضية %',
                      hint: 'مثال: 14',
                      enabled: !_isSaving,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _validatePercent,
                    ),
                    const SizedBox(height: 6),
                    const _HelperText(
                      'تُطبَّق تلقائيًا على كل فاتورة بيع جديدة. اتركها 0 لتعطيل الضريبة.',
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _maxDiscountController,
                      label: 'الحد الأقصى للخصم %',
                      hint: 'مثال: 20',
                      enabled: !_isSaving,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _validatePercent,
                    ),
                    const SizedBox(height: 6),
                    const _HelperText(
                      'أعلى نسبة خصم يمكن للكاشير تطبيقها على فاتورة. 0 = لا خصومات مسموحة.',
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ---- Business rules ----
                const _SectionHeader(
                  title: 'قواعد البيع',
                  icon: Icons.rule_outlined,
                ),
                const SizedBox(height: 10),
                _Card(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: const Text('السماح بالبيع بدون رصيد'),
                      subtitle: const Text(
                        'يتيح للكاشير بيع منتج حتى لو كان رصيده صفرًا أو أقل من الكمية المطلوبة.',
                      ),
                      value: _allowSaleWithoutStock,
                      onChanged: _isSaving
                          ? null
                          : (bool value) {
                              setState(
                                  () => _allowSaleWithoutStock = value);
                            },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      title: const Text('السماح بالبيع الآجل'),
                      subtitle: const Text(
                        'يتيح إتمام البيع مع ترك المبلغ مستحقًا على رصيد العميل.',
                      ),
                      value: _allowCreditSale,
                      onChanged: _isSaving
                          ? null
                          : (bool value) {
                              setState(() => _allowCreditSale = value);
                            },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ---- Receipt ----
                const _SectionHeader(
                  title: 'تذييل الإيصال',
                  icon: Icons.text_fields_outlined,
                ),
                const SizedBox(height: 10),
                _Card(
                  children: <Widget>[
                    AppTextField(
                      controller: _footerController,
                      label: 'النص أسفل الإيصال',
                      hint: 'شكرًا لتعاملكم معنا',
                      enabled: !_isSaving,
                      maxLines: 3,
                      validator: _validateFooter,
                    ),
                    const SizedBox(height: 6),
                    const _HelperText(
                      'يظهر في نهاية كل إيصال PDF أو حراري (حتى 200 حرف).',
                    ),
                    const SizedBox(height: 10),
                    _PreviewFooter(controller: _footerController),
                  ],
                ),

                if (_saveFailure != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _saveFailureMessage(_saveFailure!)),
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
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Validators
  // ---------------------------------------------------------------------------

  String? _validatePercent(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'الرجاء إدخال قيمة';
    final double? parsed = double.tryParse(trimmed);
    if (parsed == null) return 'الرجاء إدخال رقم صحيح';
    if (parsed < 0) return 'لا يمكن أن تكون القيمة سالبة';
    if (parsed > 100) return 'القيمة يجب ألا تتجاوز 100';
    return null;
  }

  String? _validateFooter(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'الرجاء إدخال نص التذييل';
    if (trimmed.length > 200) {
      return 'النص طويل جدًا (الحد الأقصى 200 حرف)';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Localization
  // ---------------------------------------------------------------------------

  static String _errorMessage(Object error) {
    if (error is CompanySettingsException) {
      return _failureMessage(error.type);
    }
    return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
  }

  static String _saveFailureMessage(CompanySettingsFailureType type) =>
      _failureMessage(type);

  static String _failureMessage(CompanySettingsFailureType type) {
    switch (type) {
      case CompanySettingsFailureType.network:
        return 'تعذّر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.';
      case CompanySettingsFailureType.unauthorized:
        return 'ليس لديك صلاحية لتعديل الإعدادات. تواصل مع مدير الشركة.';
      case CompanySettingsFailureType.notFound:
        return 'لم يتم العثور على إعدادات هذه الشركة.';
      case CompanySettingsFailureType.invalidTaxRate:
        return 'نسبة الضريبة يجب أن تكون بين 0 و 100.';
      case CompanySettingsFailureType.invalidDiscountLimit:
        return 'حد الخصم يجب أن يكون بين 0 و 100.';
      case CompanySettingsFailureType.invalidFooter:
        return 'نص التذييل غير صالح (فارغ أو يتجاوز 200 حرف).';
      case CompanySettingsFailureType.invalidResponse:
        return 'تعذّر قراءة البيانات من الخادم.';
      case CompanySettingsFailureType.unknown:
        return 'تعذّر حفظ الإعدادات. حاول مرة أخرى.';
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
  const _Card({required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

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
        padding: padding ?? const EdgeInsets.all(14),
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
// Footer preview
// ============================================================================

class _PreviewFooter extends StatelessWidget {
  const _PreviewFooter({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (
        BuildContext context,
        TextEditingValue value,
        Widget? _,
      ) {
        final String text = value.text.trim();
        final String display = text.isEmpty ? '—' : text;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'معاينة',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    display,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: text.isEmpty
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                      fontStyle: text.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
