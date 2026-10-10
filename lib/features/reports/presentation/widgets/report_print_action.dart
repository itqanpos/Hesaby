// lib/features/reports/presentation/widgets/report_print_action.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../pos/data/services/direct_print_service.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/pdf_report_builder.dart';
import '../../domain/entities/report_document.dart';

/// A button that opens a print / share dialog for a [ReportDocument].
///
/// **Phase P-2:** if "direct print" is enabled, the report is sent straight
/// to the OS default printer without opening the preview dialog. On any
/// failure, the standard dialog opens as a fallback.
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

    // Reports are always A4, so we use the A4 font scale.
    final CompanySettings? settings =
        ref.read(companySettingsProvider).valueOrNull;
    final PrintStyleSettings style = settings == null
        ? const PrintStyleSettings.defaults()
        : PrintStyleSettings(
            fontScale: settings.printFontScaleA4,
            fontWeight: settings.printFontWeight,
          );

    // ---- Direct print path ----
    final bool direct = settings?.printDirectEnabled ?? false;
    if (direct) {
      try {
        final Uint8List bytes = await PdfReportBuilder.build(
          document: doc,
          style: style,
        );
        final String name = _fileNameFor();
        final bool ok = await DirectPrintService.tryPdfBytes(
          bytes: bytes,
          name: name,
        );
        if (ok) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text('تم إرسال التقرير للطابعة.')),
              );
          }
          return;
        }
      } on Object {
        // Fall through to the preview dialog.
      }
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) =>
          _PrintDialog(document: doc, style: style),
    );
  }

  static String _fileNameFor() {
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 16);
    return 'report-$stamp.pdf';
  }
}

// ============================================================================
// Dialog
// ============================================================================

class _PrintDialog extends StatefulWidget {
  const _PrintDialog({
    required this.document,
    required this.style,
  });

  final ReportDocument document;
  final PrintStyleSettings style;

  @override
  State<_PrintDialog> createState() => _PrintDialogState();
}

class _PrintDialogState extends State<_PrintDialog> {
  bool _isPrinting = false;
  bool _isSharing = false;

  bool get _isBusy => _isPrinting || _isSharing;

  String get _fileName {
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 16);
    return 'report-$stamp.pdf';
  }

  Future<void> _print() async {
    setState(() => _isPrinting = true);
    try {
      final Uint8List bytes = await PdfReportBuilder.build(
        document: widget.document,
        style: widget.style,
      );
      await Printing.layoutPdf(
        name: _fileName,
        onLayout: (PdfPageFormat _) => bytes,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      _showFailure('تعذّرت الطباعة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _share() async {
    setState(() => _isSharing = true);
    try {
      final Uint8List bytes = await PdfReportBuilder.build(
        document: widget.document,
        style: widget.style,
      );
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      _showFailure('تعذّرت مشاركة الملف.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _showFailure(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _infoRow(theme, 'الشركة', doc.companyName),
          if (doc.branchName != null)
            _infoRow(theme, 'الفرع', doc.branchName!),
          _infoRow(theme, 'الفترة', doc.periodLabel ?? 'الكل'),
          _infoRow(theme, 'عدد الأقسام', doc.sections.length.toString()),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _isBusy ? null : _print,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
              label: const Text('طباعة'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _share,
              icon: _isSharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: const Text('مشاركة PDF'),
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
