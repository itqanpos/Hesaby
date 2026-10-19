// lib/features/pos/data/services/pdf_receipt_builder.dart

import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/receipt_number_format.dart';

enum ReceiptPaperSize {
  mm58,
  mm80,
  a4,
}

abstract final class PdfReceiptBuilder {
  static Future<pw.Font>? _regularFontFuture;
  static Future<pw.Font>? _boldFontFuture;

  static Future<pw.Font> _regularFont() => _regularFontFuture ??=
      _loadBundledOr('Cairo-Regular.ttf', PdfGoogleFonts.cairoRegular);

  static Future<pw.Font> _boldFont() => _boldFontFuture ??=
      _loadBundledOr('Cairo-Bold.ttf', PdfGoogleFonts.cairoBold);

  static Future<pw.Font> _loadBundledOr(String fileName, Future<pw.Font> Function() fallback) async {
    try {
      final ByteData data = await rootBundle.load('assets/fonts/$fileName');
      return pw.Font.ttf(data);
    } on Object {
      return fallback();
    }
  }

  static const List<String> _arabicDays = <String>['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  static const String _defaultFooter = 'شكرًا لتعاملكم معنا';
  static const String _currency = 'ج.م';

  static const double _thermalFixedMm = 120;
  static const double _thermalPerLineMm = 14;

  static double _thermalHeightFor(int lineCount) {
    final double estimatedMm = _thermalFixedMm + lineCount * _thermalPerLineMm;
    final double clampedMm = estimatedMm.clamp(170.0, 400.0);
    return clampedMm * PdfPageFormat.mm;
  }

  static Future<Uint8List> build({
    required Receipt receipt,
    required ReceiptPaperSize size,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  }) async {
    final pw.ThemeData theme = await _loadTheme();

    final PdfPageFormat pageFormat;
    final double padding;
    switch (size) {
      case ReceiptPaperSize.mm58:
        pageFormat = PdfPageFormat(58 * PdfPageFormat.mm, _thermalHeightFor(receipt.lines.length), marginAll: 0);
        padding = 4;
      case ReceiptPaperSize.mm80:
        pageFormat = PdfPageFormat(80 * PdfPageFormat.mm, _thermalHeightFor(receipt.lines.length), marginAll: 0);
        padding = 6;
      case ReceiptPaperSize.a4:
        pageFormat = PdfPageFormat.a4;
        padding = 28;
    }

    final pw.Document document = pw.Document(
      theme: theme,
      title: receipt.invoiceNumber ?? receipt.saleId,
      author: receipt.companyName,
      creator: 'Hesabi',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(padding),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) => _buildContent(receipt: receipt, paperSize: size, style: style, logoBytes: logoBytes),
      ),
    );

    return document.save();
  }

  static Future<pw.ThemeData> _loadTheme() async {
    final pw.Font regular = await _regularFont();
    final pw.Font bold = await _boldFont();
