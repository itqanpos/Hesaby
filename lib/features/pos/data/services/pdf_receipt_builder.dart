// lib/features/pos/data/services/pdf_receipt_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/entities/receipt.dart';

/// Supported paper sizes for a printed receipt.
enum ReceiptPaperSize {
  mm58,
  mm80,
  a4,
}

/// Builds a PDF document from a [Receipt].
///
/// Design follows the classic small-business invoice layout:
/// * Centred company name + branch.
/// * Bordered "فاتورة مبيعات" title.
/// * Dashed divider, then a labelled info block.
/// * A bordered 5-column table: م | الصنف | الكمية | السعر | الإجمالي.
/// * Subtotal row inside the table.
/// * Bottom summary with each value inside a small bordered box.
///
/// Fonts are cached across calls (see [_regularFont]).
abstract final class PdfReceiptBuilder {
  // ---------------------------------------------------------------------------
  // Font cache
  // ---------------------------------------------------------------------------

  static Future<pw.Font>? _regularFontFuture;
  static Future<pw.Font>? _boldFontFuture;

  static Future<pw.Font> _regularFont() =>
      _regularFontFuture ??= PdfGoogleFonts.cairoRegular();

  static Future<pw.Font> _boldFont() =>
      _boldFontFuture ??= PdfGoogleFonts.cairoBold();

  // ---------------------------------------------------------------------------
  // Arabic day names, indexed by [DateTime.weekday] (1 = Monday).
  // ---------------------------------------------------------------------------

  static const List<String> _arabicDays = <String>[
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  // ---------------------------------------------------------------------------
  // Thermal sizing
  // ---------------------------------------------------------------------------

  static const double _thermalFixedMm = 120;
  static const double _thermalPerLineMm = 14;

  static double _thermalHeightFor(int lineCount) {
    final double estimatedMm =
        _thermalFixedMm + lineCount * _thermalPerLineMm;
    final double clampedMm = estimatedMm.clamp(170.0, 400.0);
    return clampedMm * PdfPageFormat.mm;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static Future<Uint8List> build({
    required Receipt receipt,
    required ReceiptPaperSize size,
  }) async {
    final pw.ThemeData theme = await _loadTheme();

    final PdfPageFormat pageFormat;
    final double padding;
    switch (size) {
      case ReceiptPaperSize.mm58:
        pageFormat = PdfPageFormat(
          58 * PdfPageFormat.mm,
          _thermalHeightFor(receipt.lines.length),
          marginAll: 0,
        );
        padding = 4;
      case ReceiptPaperSize.mm80:
        pageFormat = PdfPageFormat(
          80 * PdfPageFormat.mm,
          _thermalHeightFor(receipt.lines.length),
          marginAll: 0,
        );
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
        build: (pw.Context context) => _buildContent(
          receipt: receipt,
          paperSize: size,
        ),
      ),
    );

    return document.save();
  }

  // ---------------------------------------------------------------------------
  // Fonts
  // ---------------------------------------------------------------------------

  static Future<pw.ThemeData> _loadTheme() async {
    final pw.Font regular = await _regularFont();
    final pw.Font bold = await _boldFont();
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildContent({
    required Receipt receipt,
    required ReceiptPaperSize paperSize,
  }) {
    final bool isThermal = paperSize != ReceiptPaperSize.a4;
    final double baseFont = isThermal ? 8 : 10;
    final double headerFont = isThermal ? 11 : 16;
    final double titleFont = isThermal ? 9 : 12;
    final double smallFont = isThermal ? 7 : 9;
    final double grandFont = isThermal ? 10 : 13;
    final double tableFont = isThermal ? 7.5 : 9;

    return <pw.Widget>[
      // ---- Company header ----
      pw.Center(
        child: pw.Text(
          receipt.companyName,
          style: pw.TextStyle(
            fontSize: headerFont,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          receipt.branchName,
          style: pw.TextStyle(fontSize: baseFont),
          textAlign: pw.TextAlign.center,
        ),
      ),

      pw.SizedBox(height: 8),

      // ---- Boxed "فاتورة مبيعات" ----
      pw.Center(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 3,
          ),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: PdfColors.black,
              width: 0.8,
            ),
            borderRadius: const pw.BorderRadius.all(
              pw.Radius.circular(2),
            ),
          ),
          child: pw.Text(
            'فاتورة مبيعات',
            style: pw.TextStyle(
              fontSize: titleFont,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ),

      pw.SizedBox(height: 8),

      // ---- Dashed divider ----
      pw.Container(
        width: double.infinity,
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              width: 0.6,
              color: PdfColors.grey700,
              style: pw.BorderStyle.dashed,
            ),
          ),
        ),
      ),

      pw.SizedBox(height: 6),

      // ---- Info block ----
      _infoRow('رقم الفاتورة', receipt.invoiceNumber ?? '—', baseFont,
          boldValue: true),
      _infoRow('التاريخ', _formatDayAndDate(receipt.dateTime), baseFont),
      if (receipt.hasCustomer)
        _infoRow('العميل', receipt.customerName!, baseFont),
      if (receipt.cashierName != null)
        _infoRow('الكاشير', receipt.cashierName!, baseFont),

      pw.SizedBox(height: 6),

      // ---- Items table ----
      _buildItemsTable(
        receipt: receipt,
        isThermal: isThermal,
        baseFont: tableFont,
        headerFont: tableFont,
      ),

      pw.SizedBox(height: 8),

      // ---- Bottom summary with boxed values ----
      _buildBottomSummary(
        receipt: receipt,
        labelFont: baseFont,
        valueFont: isThermal ? 9 : 11,
        grandFont: grandFont,
      ),

      pw.SizedBox(height: 12),

      // ---- Footer ----
      pw.Center(
        child: pw.Text(
          'شكرًا لتعاملكم معنا',
          style: pw.TextStyle(
            fontSize: baseFont,
            color: PdfColors.grey700,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Info row: `label:` on the right, value on the left
  // ---------------------------------------------------------------------------

  static pw.Widget _infoRow(
    String label,
    String value,
    double fontSize, {
    bool boldValue = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 76,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: boldValue
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Items table
  // ---------------------------------------------------------------------------

  static pw.Widget _buildItemsTable({
    required Receipt receipt,
    required bool isThermal,
    required double baseFont,
    required double headerFont,
  }) {
    const double padH = 3;
    const double padV = 3;

    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.grey800,
        width: 0.5,
      ),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: isThermal
          ? const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(16),   // م
              1: pw.FlexColumnWidth(3.0),   // الصنف
              2: pw.FlexColumnWidth(1.4),   // الكمية
              3: pw.FlexColumnWidth(1.2),   // السعر
              4: pw.FlexColumnWidth(1.5),   // الإجمالي
            }
          : const <int, pw.TableColumnWidth>{
              0: pw.FixedColumnWidth(28),
              1: pw.FlexColumnWidth(3.0),
              2: pw.FlexColumnWidth(1.3),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FlexColumnWidth(1.5),
            },
      children: <pw.TableRow>[
        // ---- Header row ----
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: <pw.Widget>[
            _cell('م',
                fontSize: headerFont, bold: true, center: true,
                padH: padH, padV: padV),
            _cell('الصنف',
                fontSize: headerFont, bold: true,
                padH: padH, padV: padV),
            _cell('الكمية',
                fontSize: headerFont, bold: true, center: true,
                padH: padH, padV: padV),
            _cell('السعر',
                fontSize: headerFont, bold: true, center: true,
                padH: padH, padV: padV),
            _cell('الإجمالي',
                fontSize: headerFont, bold: true, center: true,
                padH: padH, padV: padV),
          ],
        ),

        // ---- Item rows ----
        for (int i = 0; i < receipt.lines.length; i++)
          pw.TableRow(
            children: <pw.Widget>[
              _cell('${i + 1}',
                  fontSize: baseFont, center: true,
                  padH: padH, padV: padV),
              _cell(
                receipt.lines[i].productName,
                fontSize: baseFont,
                padH: padH,
                padV: padV,
              ),
              _cell(
                '${_formatQuantity(receipt.lines[i].quantity)} '
                '${receipt.lines[i].unitName}',
                fontSize: baseFont, center: true,
                padH: padH, padV: padV,
              ),
              _cell(
                _formatNumber(receipt.lines[i].unitPrice),
                fontSize: baseFont, center: true,
                padH: padH, padV: padV,
              ),
              _cell(
                _formatNumber(receipt.lines[i].lineTotal),
                fontSize: baseFont, bold: true, center: true,
                padH: padH, padV: padV,
              ),
            ],
          ),

        // ---- Subtotal row ----
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: <pw.Widget>[
            _cell('',
                fontSize: baseFont,
                padH: padH, padV: padV),
            _cell('المجموع الفرعي',
                fontSize: baseFont, bold: true,
                padH: padH, padV: padV),
            _cell('${receipt.lines.length}',
                fontSize: baseFont, center: true,
                padH: padH, padV: padV),
            _cell('',
                fontSize: baseFont,
                padH: padH, padV: padV),
            _cell(_formatNumber(receipt.subtotal),
                fontSize: baseFont, bold: true, center: true,
                padH: padH, padV: padV),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    required double fontSize,
    bool bold = false,
    bool center = false,
    required double padH,
    required double padV,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: padH,
        vertical: padV,
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight:
              bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.right,
        softWrap: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom summary (boxed values)
  // ---------------------------------------------------------------------------

  static pw.Widget _buildBottomSummary({
    required Receipt receipt,
    required double labelFont,
    required double valueFont,
    required double grandFont,
  }) {
    final double remaining = receipt.total - receipt.paidAmount;
    final double amountRemaining = remaining > 0 ? remaining : 0;
    final double? previousBalance = receipt.previousBalance;
    final double? newBalance = receipt.newBalance;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        // ---- إجمالي الفاتورة ----
        _boxedRow(
          label: 'إجمالي الفاتورة',
          value: _formatNumber(receipt.total),
          labelFont: labelFont,
          valueFont: grandFont,
          boldValue: true,
        ),

        pw.SizedBox(height: 4),

        // ---- طريقة الدفع ----
        _plainRow(
          label: 'طريقة الدفع',
          value: _paymentMethodLabel(receipt),
          labelFont: labelFont,
        ),

        // ---- صافي الرصيد السابق ----
        if (previousBalance != null) ...<pw.Widget>[
          pw.SizedBox(height: 4),
          _boxedRow(
            label: 'صافي الرصيد السابق',
            value: _formatNumber(previousBalance),
            labelFont: labelFont,
            valueFont: valueFont,
          ),
        ],

        pw.SizedBox(height: 4),

        // ---- إجمالي المدفوع ----
        _boxedRow(
          label: 'المدفوع',
          value: _formatNumber(receipt.paidAmount),
          labelFont: labelFont,
          valueFont: valueFont,
        ),

        // ---- المتبقي (only when not fully paid) ----
        if (amountRemaining > 0) ...<pw.Widget>[
          pw.SizedBox(height: 4),
          _boxedRow(
            label: 'المتبقي على العميل',
            value: _formatNumber(amountRemaining),
            labelFont: labelFont,
            valueFont: valueFont,
          ),
        ],

        // ---- صافي الرصيد بعد الفاتورة ----
        if (newBalance != null) ...<pw.Widget>[
          pw.SizedBox(height: 4),
          _boxedRow(
            label: 'صافي الرصيد بعد الفاتورة',
            value: _formatNumber(newBalance),
            labelFont: labelFont,
            valueFont: valueFont,
          ),
        ],
      ],
    );
  }

  static pw.Widget _boxedRow({
    required String label,
    required String value,
    required double labelFont,
    required double valueFont,
    bool boldValue = false,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: labelFont,
              fontWeight: pw.FontWeight.bold,
            ),
            softWrap: true,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Container(
          constraints: const pw.BoxConstraints(minWidth: 72),
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 3,
          ),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: PdfColors.grey700,
              width: 0.5,
            ),
            borderRadius: const pw.BorderRadius.all(
              pw.Radius.circular(2),
            ),
          ),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: valueFont,
              fontWeight: boldValue
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    );
  }

  static pw.Widget _plainRow({
    required String label,
    required String value,
    required double labelFont,
  }) {
    return pw.Row(
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: labelFont,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(width: 6),
        pw.SizedBox(
          width: 88,
          child: pw.Text(
            value,
            style: pw.TextStyle(fontSize: labelFont),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return _addThousandsSeparator(value.toInt().toString());
    }
    return value.toStringAsFixed(2);
  }

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static String _addThousandsSeparator(String intStr) {
    final bool negative = intStr.startsWith('-');
    final String digits = negative ? intStr.substring(1) : intStr;
    final StringBuffer buf = StringBuffer();
    if (negative) buf.write('-');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buf.write(',');
      }
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  /// Returns `"الأحد 2026/10/05 02:55 م"`.
  static String _formatDayAndDate(DateTime value) {
    final DateTime local = value.toLocal();
    final int wd = local.weekday;
    final String day = _arabicDays[(wd - 1).clamp(0, 6)];
    final String y = local.year.toString().padLeft(4, '0');
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    final int hour24 = local.hour;
    final int hour12 =
        hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final String ampm = hour24 >= 12 ? 'م' : 'ص';
    final String hh = hour12.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    return '$day  $y/$m/$d  $hh:$mm $ampm';
  }

  static String _paymentMethodLabel(Receipt receipt) {
    if (receipt.paidAmount <= 0) {
      return 'آجل';
    }
    if (receipt.paidAmount >= receipt.total) {
      return 'نقدي';
    }
    return 'نقدي (جزئي)';
  }
}
