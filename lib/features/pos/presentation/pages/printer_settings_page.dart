// lib/features/pos/presentation/pages/printer_settings_page.dart

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/repositories/company_settings_repository.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../../settings/presentation/widgets/print_font_settings_section.dart';
import '../../data/services/esc_pos_test_ticket.dart';
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/printer_service.dart';
import '../../domain/entities/printer_device.dart';
import '../providers/printer_providers.dart';
import '../widgets/printer_scan_sheet.dart';

/// Printer settings page.
class PrinterSettingsPage extends ConsumerStatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  ConsumerState<PrinterSettingsPage> createState() =>
      _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends ConsumerState<PrinterSettingsPage> {
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isTesting = false;
  bool _isSavingToggle = false;
  bool _isSavingPrintOption = false;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _autoConnect() async {
    final SavedPrinter? saved = ref.read(savedPrinterProvider).valueOrNull;
    if (saved == null) return;
    await _connect(saved);
  }

  Future<void> _connect(SavedPrinter printer) async {
    setState(() {
      _isConnecting = true;
      _isConnected = false;
    });

    final PrinterService service = ref.read(printerServiceProvider);
    final bool ok = await service.connect(printer.toDevice());

    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _isConnected = ok;
    });

    if (!ok && mounted) {
      _snack('تعذّر الاتصال بالطابعة. تأكد من توصيلها وتشغيلها.');
    }
  }

  Future<void> _disconnect() async {
    await ref.read(printerServiceProvider).disconnect();
    if (!mounted) return;
    setState(() => _isConnected = false);
  }

  Future<void> _pickPrinter() async {
    final PrinterDevice? picked =
        await showPrinterScanSheet(context: context);
    if (picked == null || !mounted) return;

    final SavedPrinter saved = SavedPrinter.fromDevice(picked);
    try {
      await ref.read(savedPrinterProvider.notifier).save(saved);
      if (!mounted) return;
      await _connect(saved);
    } on Object catch (error, stackTrace) {
      AppLogger.error('Failed to save printer', error, stackTrace);
      if (!mounted) return;
      _snack('تعذّر حفظ الطابعة. حاول مرة أخرى.');
    }
  }

  Future<void> _forgetPrinter() async {
    await _disconnect();
    try {
      await ref.read(savedPrinterProvider.notifier).clear();
      if (!mounted) return;
      _snack('تم نسيان الطابعة.');
    } on Object catch (error, stackTrace) {
      AppLogger.error('Failed to forget printer', error, stackTrace);
      if (!mounted) return;
      _snack('تعذّر نسيان الطابعة.');
    }
  }

  Future<void> _testPrint() async {
    setState(() => _isTesting = true);

    try {
      final List<int> bytes = await EscPosTestTicket.build();
      await ref.read(printerServiceProvider).sendBytes(bytes);
      if (!mounted) return;
      _snack('تم إرسال الأمر للطابعة.');
    } on PrinterException catch (error) {
      if (!mounted) return;
      _snack(_messageFor(error.type));
    } on Object catch (error, stackTrace) {
      AppLogger.error('Test print failed', error, stackTrace);
      if (!mounted) return;
      _snack('تعذّرت الطباعة. تحقق من الطابعة.');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _toggleDirectPrint(bool value) async {
    if (_isSavingToggle) return;
    setState(() => _isSavingToggle = true);

    try {
      await ref.read(companySettingsProvider.notifier).updateSettings(
            printDirectEnabled: value,
          );
    } on CompanySettingsException catch (e) {
      if (!mounted) return;
      _snack(_settingsMessage(e.type));
    } on Object {
      if (!mounted) return;
      _snack('تعذّر حفظ الإعداد. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isSavingToggle = false);
    }
  }

  Future<void> _savePrintOption({
    bool? showTaxNumberOnPrint,
    bool? showCommercialRegisterOnPrint,
    bool? showCurrencySymbol,
  }) async {
    if (_isSavingPrintOption) return;
    setState(() => _isSavingPrintOption = true);

    try {
      await ref.read(companySettingsProvider.notifier).updateSettings(
            showTaxNumberOnPrint: showTaxNumberOnPrint,
            showCommercialRegisterOnPrint: showCommercialRegisterOnPrint,
            showCurrencySymbol: showCurrencySymbol,
          );
    } on CompanySettingsException catch (e) {
      if (!mounted) return;
      _snack(_settingsMessage(e.type));
    } on Object {
      if (!mounted) return;
      _snack('تعذّر حفظ الإعداد. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isSavingPrintOption = false);
    }
  }

  Future<void> _setPaperSize(ReceiptPaperSize size) async {
    try {
      await ref.read(posPaperSizeProvider.notifier).setPaperSize(size);
    } on Object catch (error, stackTrace) {
      AppLogger.error('Failed to save paper size', error, stackTrace);
      if (!mounted) return;
      _snack('تعذّر حفظ حجم الورق.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _messageFor(PrinterFailureType type) {
    switch (type) {
      case PrinterFailureType.notSupported:
        return 'الطباعة غير مدعومة على هذه المنصة.';
      case PrinterFailureType.connectFailed:
        return 'تعذّر الاتصال بالطابعة.';
      case PrinterFailureType.notConnected:
        return 'لا توجد طابعة متصلة.';
      case PrinterFailureType.sendFailed:
        return 'تعذّر إرسال البيانات للطابعة.';
      case PrinterFailureType.unknown:
        return 'حدث خطأ غير متوقع.';
    }
  }

  static String _settingsMessage(CompanySettingsFailureType t) => switch (t) {
        CompanySettingsFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
        CompanySettingsFailureType.unauthorized =>
          'لا تملك صلاحية تعديل الإعدادات.',
        CompanySettingsFailureType.notFound => 'لم يتم العثور على الإعدادات.',
        CompanySettingsFailureType.invalidTaxRate => 'قيمة غير صحيحة.',
        CompanySettingsFailureType.invalidDiscountLimit => 'قيمة غير صحيحة.',
        CompanySettingsFailureType.invalidFooter => 'قيمة غير صحيحة.',
        CompanySettingsFailureType.invalidResponse =>
          'تعذّر قراءة البيانات.',
        CompanySettingsFailureType.unknown =>
          'حدث خطأ غير متوقع. حاول مرة أخرى.',
      };

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SavedPrinter?> savedAsync =
        ref.watch(savedPrinterProvider);

    return AppShell(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('إعدادات الطابعة'),
      ),
      body: savedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _ErrorBody(
          message: 'تعذّر تحميل إعدادات الطابعة.',
          onRetry: () => ref.invalidate(savedPrinterProvider),
        ),
        data: (SavedPrinter? saved) => _buildBody(saved),
      ),
    );
  }

  Widget _buildBody(SavedPrinter? saved) {
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: <Widget>[
        // ---- Printer ----
        if (saved == null)
          _NoPrinterBody(onPick: _pickPrinter, isDesktop: _isDesktop)
        else
          _SavedPrinterBody(
            saved: saved,
            isConnecting: _isConnecting,
            isConnected: _isConnected,
            isTesting: _isTesting,
            isDesktop: _isDesktop,
            onConnect: () => _connect(saved),
            onTest: _testPrint,
            onPick: _pickPrinter,
            onForget: _forgetPrinter,
          ),

        const SizedBox(height: 24),

        // ---- Direct print toggle ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _DirectPrintToggle(
            isSaving: _isSavingToggle,
            isDesktop: _isDesktop,
            onChanged: _toggleDirectPrint,
          ),
        ),

        const SizedBox(height: 24),

        // ---- Paper size ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _PaperSizeSection(
            enabled: !_isSavingPrintOption,
            onChanged: _setPaperSize,
          ),
        ),

        const SizedBox(height: 24),

        // ---- Print options ----
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _PrintOptionsSection(
            isSaving: _isSavingPrintOption,
            onChanged: _savePrintOption,
          ),
        ),

        const SizedBox(height: 24),

        // ---- Receipt footer ----
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: _ReceiptFooterSection(),
        ),

        const SizedBox(height: 24),

        // ---- Font settings ----
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: PrintFontSettingsSection(),
        ),
      ],
    );
  }
}

// ============================================================================
// Paper size section
// ============================================================================

class _PaperSizeSection extends ConsumerWidget {
  const _PaperSizeSection({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<ReceiptPaperSize> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ReceiptPaperSize current =
        ref.watch(posPaperSizeProvider).valueOrNull ??
            PosPreferences.defaultPaperSize;

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
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.straighten_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  'حجم الورق',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'يُستخدم عند الطباعة الحرارية على هذا الجهاز.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ReceiptPaperSize>(
              segments: const <ButtonSegment<ReceiptPaperSize>>[
                ButtonSegment<ReceiptPaperSize>(
                  value: ReceiptPaperSize.mm58,
                  label: Text('58 mm'),
                  icon: Icon(Icons.print_outlined, size: 18),
                ),
                ButtonSegment<ReceiptPaperSize>(
                  value: ReceiptPaperSize.mm80,
                  label: Text('80 mm'),
                  icon: Icon(Icons.print_outlined, size: 18),
                ),
              ],
              selected: <ReceiptPaperSize>{current},
              onSelectionChanged: enabled
                  ? (Set<ReceiptPaperSize> s) => onChanged(s.first)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              'يُحفظ على هذا الجهاز فقط — يمكنك تغييره على جهاز آخر.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Print options section
// ============================================================================

class _PrintOptionsSection extends ConsumerWidget {
  const _PrintOptionsSection({
    required this.isSaving,
    required this.onChanged,
  });

  final bool isSaving;
  final void Function({
    bool? showTaxNumberOnPrint,
    bool? showCommercialRegisterOnPrint,
    bool? showCurrencySymbol,
  }) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CompanySettings settings =
        ref.watch(companySettingsProvider).valueOrNull ??
            CompanySettings.defaults('');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(
              children: <Widget>[
                Icon(Icons.tune, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  'خيارات الطباعة',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('الرقم الضريبي في الفاتورة'),
            subtitle: const Text(
              'يُطبع الرقم الضريبي للشركة أسفل اسم الفرع.',
            ),
            value: settings.showTaxNumberOnPrint,
            onChanged: isSaving
                ? null
                : (bool v) =>
                    onChanged(showTaxNumberOnPrint: v),
            secondary: Icon(
              settings.showTaxNumberOnPrint
                  ? Icons.check_circle_outline
                  : Icons.circle_outlined,
              color: settings.showTaxNumberOnPrint
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('السجل التجاري في الفاتورة'),
            subtitle: const Text(
              'يُطبع السجل التجاري للشركة أسفل اسم الفرع.',
            ),
            value: settings.showCommercialRegisterOnPrint,
            onChanged: isSaving
                ? null
                : (bool v) =>
                    onChanged(showCommercialRegisterOnPrint: v),
            secondary: Icon(
              settings.showCommercialRegisterOnPrint
                  ? Icons.check_circle_outline
                  : Icons.circle_outlined,
              color: settings.showCommercialRegisterOnPrint
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('إظهار رمز العملة (ج.م)'),
            subtitle: const Text(
              'عند التعطيل تُطبع المبالغ أرقامًا فقط بدون رمز العملة.',
            ),
            value: settings.showCurrencySymbol,
            onChanged: isSaving
                ? null
                : (bool v) => onChanged(showCurrencySymbol: v),
            secondary: Icon(
              settings.showCurrencySymbol
                  ? Icons.check_circle_outline
                  : Icons.circle_outlined,
              color: settings.showCurrencySymbol
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Receipt footer section
// ============================================================================

class _ReceiptFooterSection extends ConsumerStatefulWidget {
  const _ReceiptFooterSection();

  @override
  ConsumerState<_ReceiptFooterSection> createState() =>
      _ReceiptFooterSectionState();
}

class _ReceiptFooterSectionState
    extends ConsumerState<_ReceiptFooterSection> {
  static const int _maxFooterLength = 200;

  late final TextEditingController _controller;

  bool _initialized = false;
  bool _isSaving = false;
  String? _errorMessage;
  String _savedValue = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      _errorMessage = null;
    });
  }

  void _hydrate(CompanySettings settings) {
    if (_initialized) return;
    _initialized = true;
    _controller.text = settings.receiptFooter;
    _savedValue = settings.receiptFooter;
  }

  String? _validateFooter(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'الرجاء إدخال نص التذييل';
    if (trimmed.length > _maxFooterLength) {
      return 'النص طويل جدًا (الحد الأقصى $_maxFooterLength حرف)';
    }
    return null;
  }

  bool get _hasChanges => _controller.text.trim() != _savedValue.trim();

  Future<void> _save() async {
    if (_isSaving) return;
    final String? error = _validateFooter(_controller.text);
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    final String trimmed = _controller.text.trim();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(companySettingsProvider.notifier).updateSettings(
            receiptFooter: trimmed,
          );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _savedValue = trimmed;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم حفظ التذييل.')),
        );
    } on CompanySettingsException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = _footerFailureMessage(e.type);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'تعذّر حفظ التذييل. حاول مرة أخرى.';
      });
    }
  }

  static String _footerFailureMessage(CompanySettingsFailureType t) =>
      switch (t) {
        CompanySettingsFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
        CompanySettingsFailureType.unauthorized =>
          'لا تملك صلاحية تعديل الإعدادات.',
        CompanySettingsFailureType.notFound =>
          'لم يتم العثور على إعدادات الشركة.',
        CompanySettingsFailureType.invalidFooter =>
          'نص التذييل غير صالح (فارغ أو يتجاوز $_maxFooterLength حرف).',
        CompanySettingsFailureType.invalidTaxRate => 'قيمة غير صحيحة.',
        CompanySettingsFailureType.invalidDiscountLimit =>
          'قيمة غير صحيحة.',
        CompanySettingsFailureType.invalidResponse =>
          'تعذّر قراءة البيانات.',
        CompanySettingsFailureType.unknown =>
          'حدث خطأ غير متوقع. حاول مرة أخرى.',
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CompanySettings? settings =
        ref.watch(companySettingsProvider).valueOrNull;
    if (settings != null) _hydrate(settings);

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
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.text_fields_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  'تذييل الإيصال',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'يظهر في نهاية كل إيصال حراري أو PDF.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _controller,
              label: 'النص أسفل الإيصال',
              hint: 'شكرًا لتعاملكم معنا',
              enabled: !_isSaving,
              maxLines: 3,
              validator: _validateFooter,
            ),
            const SizedBox(height: 6),
            Text(
              'حتى $_maxFooterLength حرف.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _FooterPreview(controller: _controller),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              _InlineError(message: _errorMessage!),
            ],
            const SizedBox(height: 12),
            AppButton(
              label: 'حفظ التذييل',
              icon: Icons.save_outlined,
              expanded: true,
              isLoading: _isSaving,
              onPressed:
                  (!_hasChanges || _isSaving) ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Footer preview
// ============================================================================

class _FooterPreview extends StatelessWidget {
  const _FooterPreview({required this.controller});

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
// Inline error banner
// ============================================================================

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

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

// ============================================================================
// Direct print toggle
// ============================================================================

class _DirectPrintToggle extends ConsumerWidget {
  const _DirectPrintToggle({
    required this.isSaving,
    required this.isDesktop,
    required this.onChanged,
  });

  final bool isSaving;
  final bool isDesktop;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool enabled =
        ref.watch(companySettingsProvider).valueOrNull?.printDirectEnabled ??
            false;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: const Text('الطباعة المباشرة'),
        subtitle: Text(
          isDesktop
              ? 'تجاوز حوار المعاينة واطبع فورًا على طابعة USB المتصلة.'
              : 'تجاوز حوار المعاينة واطبع فورًا على طابعة Bluetooth المتصلة.',
        ),
        value: enabled,
        onChanged: isSaving ? null : onChanged,
        secondary: Icon(
          enabled ? Icons.flash_on : Icons.flash_off,
          color: enabled ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ============================================================================
// No printer
// ============================================================================

class _NoPrinterBody extends StatelessWidget {
  const _NoPrinterBody({required this.onPick, required this.isDesktop});

  final VoidCallback onPick;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 24),
        Icon(
          Icons.print_disabled_outlined,
          size: 56,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          'لم تختر طابعة بعد',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          isDesktop
              ? 'اختر طابعة حرارية متصلة بكابل USB لطباعة الإيصالات.'
              : 'اختر طابعة حرارية لطباعة إيصالات نقطة البيع مباشرة.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AppButton(
            label: 'اختيار طابعة',
            icon: isDesktop ? Icons.usb : Icons.search,
            expanded: true,
            size: AppButtonSize.large,
            onPressed: onPick,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Saved printer
// ============================================================================

class _SavedPrinterBody extends StatelessWidget {
  const _SavedPrinterBody({
    required this.saved,
    required this.isConnecting,
    required this.isConnected,
    required this.isTesting,
    required this.isDesktop,
    required this.onConnect,
    required this.onTest,
    required this.onPick,
    required this.onForget,
  });

  final SavedPrinter saved;
  final bool isConnecting;
  final bool isConnected;
  final bool isTesting;
  final bool isDesktop;
  final VoidCallback onConnect;
  final VoidCallback onTest;
  final VoidCallback onPick;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isUsb = saved.connectionType == PrinterConnectionType.usb;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        isUsb ? Icons.usb : Icons.print_outlined,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              saved.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isUsb ? 'طابعة USB' : saved.address,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusChip(
                        isConnecting: isConnecting,
                        isConnected: isConnected,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _typeLabel(saved.connectionType),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!isConnected && !isConnecting)
                AppButton(
                  label: 'الاتصال بالطابعة',
                  icon: Icons.link,
                  expanded: true,
                  size: AppButtonSize.large,
                  onPressed: onConnect,
                ),
              if (isConnected)
                AppButton(
                  label: 'طباعة تجريبية',
                  icon: Icons.print_outlined,
                  expanded: true,
                  size: AppButtonSize.large,
                  isLoading: isTesting,
                  onPressed: isTesting ? null : onTest,
                ),
              const SizedBox(height: 8),
              AppButton(
                label: 'اختيار طابعة أخرى',
                icon: Icons.swap_horiz,
                variant: AppButtonVariant.secondary,
                expanded: true,
                onPressed: isConnecting ? null : onPick,
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'نسيان الطابعة',
                icon: Icons.delete_outline,
                variant: AppButtonVariant.danger,
                expanded: true,
                onPressed: isConnecting ? null : onForget,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            isDesktop
                ? 'ملاحظة: تأكد من توصيل الطابعة بالكمبيوتر عبر كابل USB وتعريفها في إعدادات ويندوز.'
                : 'ملاحظة: الاتصال بالطابعة يبقى نشطًا أثناء استخدام التطبيق فقط. عند إعادة فتح التطبيق، سيُعاد الاتصال تلقائيًا بالطابعة المحفوظة.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _typeLabel(PrinterConnectionType type) {
    switch (type) {
      case PrinterConnectionType.bluetoothClassic:
        return 'بلوتوث (Classic)';
      case PrinterConnectionType.bluetoothBle:
        return 'بلوتوث (BLE)';
      case PrinterConnectionType.usb:
        return 'USB (كابل)';
      case PrinterConnectionType.network:
        return 'شبكة';
    }
  }
}

// ============================================================================
// Status chip
// ============================================================================

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.isConnecting,
    required this.isConnected,
  });

  final bool isConnecting;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);

    final String label;
    final Color color;
    if (isConnecting) {
      label = 'جارٍ الاتصال…';
      color = scheme.tertiary;
    } else if (isConnected) {
      label = 'متصل';
      color = scheme.primary;
    } else {
      label = 'غير متصل';
      color = scheme.onSurfaceVariant;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Error body
// ============================================================================

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            AppButton(
              label: 'إعادة المحاولة',
              icon: Icons.refresh,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
