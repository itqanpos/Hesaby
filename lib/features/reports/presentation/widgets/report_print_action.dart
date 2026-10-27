// lib/features/reports/presentation/widgets/report_print_action.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart' show Printing;

import '../../../../core/utils/logger.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../pos/data/services/direct_print_service.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/pdf_report_builder.dart';
import '../../domain/entities/report_document.dart';

/// A button that opens a print / share dialog for a [ReportDocument].
///
/// **Updates:**
/// * Removed `Printing.layoutPdf` in favour of `Printing.sharePdf`.
/// * Added paper size selection (A4 / Thermal 80mm) inside the dialog.
/// * Passed the selected size to `PdfReportBuilder`.
class ReportPrintAction extends ConsumerWidget {
  const ReportPrintAction({super.key, required this.documentBuilder});

  /// Called every time the user taps the button. Returning `null` disables
  /// the action silently.
  final ReportDocument? Function() documentBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'طباعة / مشاركة',
      icon: const Icon(Icons.ios_share),
      onPressed: () => _onPressed(context, ref),
    );
  }

  Future<void> _onPressed(BuildContext context, WidgetRef ref) async {
    final ReportDocument? raw = documentBuilder();
    if (raw == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات كافية للطباعة.')),
        );
      return;
    }

    final CompanyContextState ctx = ref.read(companyContextProvider);
    final ReportDocument doc = raw.copyWith(
      companyName: ctx.currentCompany?.name ?? raw.companyName,
      branchName: ctx.currentBranch?.name ?? raw.branchName,
    );

    // Reports are always A4 by default, but we pass the style anyway.
    final CompanySettings? settings =
        ref.read(companySettingsProvider).valueOrNull;
    final PrintStyleSettings style = settings == null
        ? const PrintStyleSettings.defaults()
        : PrintStyleSettings(
            fontScale: settings.printFontScaleA4,
            fontWeight: settings.printFontWeight,
          );

    // ---- Load logo once (non-fatal) ----
    final Uint8List? logoBytes = await _loadLogoBytes(ref);

    // ---- Direct print path (only for thermal) ----
    // Note: In this version, direct print is handled inside the dialog
    // because the user needs to choose the paper size first.
    
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => _PrintDialog(
        document: doc,
        style: style,
        logoBytes: logoBytes,
      ),
    );
  }

  /// Loads the company logo bytes for PDF embedding.
  ///
  /// Returns `null` on any failure — the report is still printable
  /// without a logo.
  static Future<Uint8List?> _loadLogoBytes(WidgetRef ref) async {
    final CompanySettings? s =
        ref.read(companySettingsProvider).valueOrNull;
    if (s == null || s.companyId.isEmpty) return null;
    try {
      return await const CompanyLogoLoader().load(
        companyId: s.companyId,
        logoUrl: s.logoUrl,
      );
    } on Object catch (e) {
      AppLogger.warning('Logo load failed (non-fatal): $e');
      return null;
    }
  }
}

// ============================================================================
// Dialog
// ============================================================================

class _PrintDialog extends ConsumerStatefulWidget {
  const _PrintDialog({
    required this.document,
    required this.style,
    required this.logoBytes,
  });

  final ReportDocument document;
  final PrintStyleSettings style;

  /// Optional company logo, embedded into every page header.
  final Uint8List? logoBytes;

  @override
  ConsumerState<_PrintDialog> createState() => _PrintDialogState();
}

class _PrintDialogState extends ConsumerState<_PrintDialog> {
  ReceiptPaperSize _selectedSize = ReceiptPaperSize.a4;
  bool _isProcessing = false;

  bool get _isBusy => _isProcessing;

  String get _fileName {
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 16);
    return 'report-$stamp.pdf';
  }

  Future<void> _export() async {
    setState(() => _isProcessing = true);
    try {
      final Uint8List bytes = await PdfReportBuilder.build(
        document: widget.document,
        style: widget.style,
        logoBytes: widget.logoBytes,
        size: _selectedSize,
      );

      // Direct print path (only if thermal and enabled)
      final bool direct = ref
              .read(companySettingsProvider)
              .valueOrNull
              ?.printDirectEnabled ??
          false;

      if (direct && _selectedSize != ReceiptPaperSize.a4) {
        final bool ok = await DirectPrintService.tryPdfBytes(
          bytes: bytes,
          name: _fileName,
        );
        if (ok) {
          if (!mounted) return;
          Navigator.of(context).pop();
          return;
        }
      }

      // ✅ شيت المشاركة (بدلاً من layoutPdf)
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object catch (e) {
      AppLogger.warning('Report export failed: $e');
      if (!mounted) return;
      _showFailure('تعذّرت الطباعة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onSizeSelected(Set<ReceiptPaperSize> selection) {
    if (selection.isEmpty || _isBusy) return;
    setState(() => _selectedSize = selection.first);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ReportDocument doc = widget.document;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.picture_as_pdf_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(doc.title, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _infoRow(theme, 'الشركة', doc.companyName),
            if (doc.branchName != null)
              _infoRow(theme, 'الفرع', doc.branchName!),
            _infoRow(theme, 'الفترة', doc.periodLabel ?? 'الكل'),
            _infoRow(theme, 'عدد الأقسام', doc.sections.length.toString()),
            const SizedBox(height: 16),
            
            // اختيار مقاس الطباعة
            Center(
              child: SegmentedButton<ReceiptPaperSize>(
                segments: const <ButtonSegment<ReceiptPaperSize>>[
                  ButtonSegment<ReceiptPaperSize>(
                    value: ReceiptPaperSize.a4,
                    label: Text('A4 (تفصيلي)'),
                  ),
                  ButtonSegment<ReceiptPaperSize>(
                    value: ReceiptPaperSize.mm80,
                    label: Text('حراري 80مم'),
                  ),
                ],
                selected: <ReceiptPaperSize>{_selectedSize},
                onSelectionChanged: _isBusy ? null : _onSizeSelected,
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            if (_selectedSize != ReceiptPaperSize.a4) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'ملاحظة: الإيصال الحراري يعرض ملخصاً فقط (KPIs). '
                'الجدول التفصيلي متاح في نسخة A4.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _isBusy ? null : _export,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: const Text('تصدير / مشاركة'),
            ),
          ],
        ),
      ],
      backgroundColor: scheme.surface,
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
