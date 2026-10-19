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
    // زيادة الارتفاع لضمان عدم الانقسام إلى صفحتين
    final double clampedMm = estimatedMm.clamp(170.0, 600.0); 
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
      // ⬇️ استخدام pw.Page بدلاً من pw.MultiPage لمنع الانقسام
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(padding),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: _buildContent(receipt: receipt, paperSize: size, style: style, logoBytes: logoBytes),
        ),
      ),
    );

    return document.save();
  }

  static Future<pw.ThemeData> _loadTheme() async {
    final pw.Font regular = await _regularFont();
    final pw.Font bold = await _boldFont();
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static pw.FontWeight _weight({required PrintFontWeight userWeight, required bool emphasized}) {
    if (emphasized || userWeight == PrintFontWeight.bold) return pw.FontWeight.bold;
    return pw.FontWeight.normal;
  }

  static List<pw.Widget> _buildContent({
    required Receipt receipt,
    required ReceiptPaperSize paperSize,
    required PrintStyleSettings style,
    Uint8List? logoBytes,
  }) {
    final _Sizes s = _Sizes.forSize(paperSize, scale: style.fontScale);

    return <pw.Widget>[
      if (logoBytes != null && logoBytes.isNotEmpty) ...<pw.Widget>[
        _buildLogo(logoBytes, s),
        pw.SizedBox(height: s.sectionGap),
      ],
      _header(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _metaBlock(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _divider(double: true),
      pw.SizedBox(height: s.sectionGap),
      _itemsTable(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _totalsSection(receipt, s, style),
      pw.SizedBox(height: s.sectionGap * 1.5),
      _divider(),
      pw.SizedBox(height: s.sectionGap),
      _footer(receipt, s, style),
    ];
  }

  // ... (بقية الدوال كما هي بدون تغيير: _totalsSection, _buildLogo, _header, _metaBlock, _metaRow, _itemsTable, _summaryRow, _cell, _kvRow, _footer, _footerText, _divider, _singleRule, _money, _qty, _formatDayAndDate, _paymentMethodLabel, _Sizes) ...
