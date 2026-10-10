// lib/features/pos/presentation/pages/printer_settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/repositories/company_settings_repository.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../../settings/presentation/widgets/print_font_settings_section.dart';
import '../../data/services/esc_pos_test_ticket.dart';
import '../../data/services/printer_service.dart';
import '../../domain/entities/printer_device.dart';
import '../providers/printer_providers.dart';
import '../widgets/printer_scan_sheet.dart';

/// Printer settings page.
///
/// Sections (top → bottom):
/// 1. **الطابعة** — pick a default thermal printer, test it, or forget it.
/// 2. **الطباعة المباشرة** — toggle to skip the preview dialog.
/// 3. **حجم وثقل الخط** — font size + weight for both thermal and A4.
class PrinterSettingsPage extends ConsumerStatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  ConsumerState<PrinterSettingsPage> createState() =>
      _PrinterSettingsPageState();
}

class _PrinterSettingsPageState
    extends ConsumerState<PrinterSettingsPage> {
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isTesting = false;
  bool _isSavingToggle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _autoConnect() async {
    final SavedPrinter? saved =
        ref.read(savedPrinterProvider).valueOrNull;
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
      _snack('تعذّر الاتصال بالطابعة. تأكد من تشغيلها.');
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
      appBar: AppBar(title: const Text('إعدادات الطابعة')),
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
          _NoPrinterBody(onPick: _pickPrinter)
        else
          _SavedPrinterBody(
            saved: saved,
            isConnecting: _isConnecting,
            isConnected: _isConnected,
            isTesting: _isTesting,
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
            onChanged: _toggleDirectPrint,
          ),
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
// Direct print toggle
// ============================================================================

class _DirectPrintToggle extends ConsumerWidget {
  const _DirectPrintToggle({
    required this.isSaving,
    required this.onChanged,
  });

  final bool isSaving;
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
        subtitle: const Text(
          'تجاوز حوار المعاينة واطبع فورًا. '
          'يعمل على Android مع طابعة Bluetooth محفوظة أو طابعة نظام افتراضية.',
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
  const _NoPrinterBody({required this.onPick});

  final VoidCallback onPick;

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
          'اختر طابعة حرارية لطباعة إيصالات نقطة البيع مباشرة.',
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
            icon: Icons.search,
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
    required this.onConnect,
    required this.onTest,
    required this.onPick,
    required this.onForget,
  });

  final SavedPrinter saved;
  final bool isConnecting;
  final bool isConnected;
  final bool isTesting;
  final VoidCallback onConnect;
  final VoidCallback onTest;
  final VoidCallback onPick;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

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
                      Icon(Icons.print_outlined, color: scheme.primary),
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
                              saved.address,
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
            'ملاحظة: الاتصال بالطابعة يبقى نشطًا أثناء استخدام التطبيق فقط. '
            'عند إعادة فتح التطبيق، سيُعاد الاتصال تلقائيًا بالطابعة المحفوظة.',
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
        return 'USB';
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
