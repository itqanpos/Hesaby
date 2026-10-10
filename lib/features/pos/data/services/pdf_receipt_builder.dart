// lib/features/pos/data/services/pdf_receipt_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/receipt.dart';

/// Supported paper sizes for a printed receipt.
enum ReceiptPaperSize {
  mm58,
  mm80,
  a4,
}

/// Builds a PDF document from a [Receipt].
///
/// Layout is optimised for thermal receipt printers:
/// * B/W/grey only — no colours (thermal printers cannot render them).
/// * Generous vertical rhythm so the cashier can scan the total at a
///   glance.
/// * Tables use alternating row backgrounds (zebra) to make multi-line
///   orders easy to read.
/// * Currency is shown explicitly on money values; quantities stay bare.
///
/// **Phase P-1b:** an optional [style] applies the user's font scale +
/// weight preferences to every text element. The default (1.0, normal)
/// matches the pre-P-1b output byte-for-byte.
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
  // Constants
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

  static const String _defaultFooter = 'شكرًا لتعاملكم معنا';
  static const String _currency = 'ج.م';

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
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
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
          style: style,
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
  // Weight resolution
  // ---------------------------------------------------------------------------

  /// Maps a semantic [PrintFontWeight] + emphasis flag to a `pdf` weight.
  ///
  /// The `pdf` package only exposes `normal` and `bold`. `medium` is
  /// therefore treated the same as `normal` for non-emphasised text;
  /// emphasised text is bold regardless.
  static pw.FontWeight _weight({
    required PrintFontWeight userWeight,
    required bool emphasized,
  }) {
    if (emphasized || userWeight == PrintFontWeight.bold) {
      return pw.FontWeight.bold;
    }
    return pw.FontWeight.normal;
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildContent({
    required Receipt receipt,
    required ReceiptPaperSize paperSize,
    required PrintStyleSettings style,
  }) {
    final _Sizes s = _Sizes.forSize(paperSize, scale: style.fontScale);

    return <pw.Widget>[
      _header(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _metaBlock(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _divider(double: true),
      pw.SizedBox(height: s.sectionGap),
      _itemsTable(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _grandTotal(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _paymentBlock(receipt, s, style),
      if (receipt.hasBalanceChange) ...<pw.Widget>[
        pw.SizedBox(height: s.sectionGap),
        _divider(),
        pw.SizedBox(height: s.sectionGap),
        _balanceBlock(receipt, s, style),
      ],
      pw.SizedBox(height: s.sectionGap * 1.5),
      _divider(),
      pw.SizedBox(height: s.sectionGap),
      _footer(receipt, s, style),
    ];
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  static pw.Widget _header(
    Receipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Center(
          child: pw.Text(
            receipt.companyName,
            style: pw.TextStyle(
              fontSize: s.companyName,
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: true,
              ),
              letterSpacing: 0.3,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Center(
          child: pw.Text(
            receipt.branchName,
            style: pw.TextStyle(
              fontSize: s.branchName,
              color: PdfColors.grey700,
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: false,
              ),
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(height: s.sectionGap),
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 5,
            ),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1),
              borderRadius: const pw.BorderRadius.all(
                pw.Radius.circular(3),
              ),
            ),
            child: pw.Text(
              'فاتورة مبيعات',
              style: pw.TextStyle(
                fontSize: s.title,
                fontWeight: _weight(
                  userWeight: style.fontWeight,
                  emphasized: true,
                ),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Meta block
  // ---------------------------------------------------------------------------

  static pw.Widget _metaBlock(
    Receipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _metaRow(
          'رقم الفاتورة',
          receipt.invoiceNumber ?? '—',
          s,
          style,
          emphasized: true,
        ),
        _metaRow(
          'التاريخ',
          _formatDayAndDate(receipt.dateTime),
          s,
          style,
        ),
        if (receipt.hasCustomer)
          _metaRow('العميل', receipt.customerName!, s, style),
        if (receipt.cashierName != null &&
            receipt.cashierName!.trim().isNotEmpty)
          _metaRow('الكاشير', receipt.cashierName!, s, style),
      ],
    );
  }

  static pw.Widget _metaRow(
    String label,
    String value,
    _Sizes s,
    PrintStyleSettings style, {
    bool emphasized = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: s.metaLabelWidth,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: s.meta,
                fontWeight: _weight(
                  userWeight: style.fontWeight,
                  emphasized: true,
                ),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: s.meta,
                fontWeight: _weight(
                  userWeight: style.fontWeight,
                  emphasized: emphasized,
                ),
              ),
              textAlign: pw.TextAlign.left,
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

  static pw.Widget _itemsTable(
    Receipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    final Map<int, pw.TableColumnWidth> columnWidths =
        <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(1.4),
      1: pw.FlexColumnWidth(1.2),
      2: pw.FlexColumnWidth(1.3),
      3: pw.FlexColumnWidth(3.0),
      4: pw.FixedColumnWidth(s.rowNumWidth),
    };

    final List<pw.TableRow> rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: <pw.Widget>[
          _cell('الإجمالي',
              fontSize: s.tableHeader,
              emphasized: true,
              center: true,
              s: s,
              style: style),
          _cell('السعر',
              fontSize: s.tableHeader,
              emphasized: true,
              center: true,
              s: s,
              style: style),
          _cell('الكمية',
              fontSize: s.tableHeader,
              emphasized: true,
              center: true,
              s: s,
              style: style),
          _cell('الصنف',
              fontSize: s.tableHeader,
              emphasized: true,
              s: s,
              style: style),
          _cell('م',
              fontSize: s.tableHeader,
              emphasized: true,
              center: true,
              s: s,
              style: style),
        ],
      ),
    ];

    for (int i = 0; i < receipt.lines.length; i++) {
      final bool zebra = i.isOdd;
      final ReceiptLine line = receipt.lines[i];
      rows.add(
        pw.TableRow(
          decoration: zebra
              ? const pw.BoxDecoration(color: PdfColors.grey100)
              : null,
          children: <pw.Widget>[
            _cell(_money(line.lineTotal),
                fontSize: s.tableRow,
                emphasized: true,
                center: true,
                s: s,
                style: style),
            _cell(_money(line.unitPrice),
                fontSize: s.tableRow, center: true, s: s, style: style),
            _cell('${_qty(line.quantity)} ${line.unitName}',
                fontSize: s.tableRow, center: true, s: s, style: style),
            _cell(line.productName,
                fontSize: s.tableRow, s: s, style: style),
            _cell('${i + 1}',
                fontSize: s.tableRow, center: true, s: s, style: style),
          ],
        ),
      );
    }

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: <pw.Widget>[
          _cell(_money(receipt.subtotal),
              fontSize: s.tableRow,
              emphasized: true,
              center: true,
              s: s,
              style: style),
          _cell('', fontSize: s.tableRow, s: s, style: style),
          _cell('${receipt.lines.length}',
              fontSize: s.tableRow, center: true, s: s, style: style),
          _cell('المجموع الفرعي',
              fontSize: s.tableRow,
              emphasized: true,
              s: s,
              style: style),
          _cell('', fontSize: s.tableRow, s: s, style: style),
        ],
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColors.grey700,
        width: 0.5,
      ),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: rows,
    );
  }

  static pw.Widget _cell(
    String text, {
    required double fontSize,
    required _Sizes s,
    required PrintStyleSettings style,
    bool emphasized = false,
    bool center = false,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: s.cellPadH,
        vertical: s.cellPadV,
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: _weight(
            userWeight: style.fontWeight,
            emphasized: emphasized,
          ),
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.right,
        softWrap: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Grand total
  // ---------------------------------------------------------------------------

  static pw.Widget _grandTotal(
    Receipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(
        horizontal: s.cellPadH * 2,
        vertical: s.cellPadV * 1.5,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.2),
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(3),
        ),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              'إجمالي الفاتورة',
              style: pw.TextStyle(
                fontSize: s.grandTotal,
                fontWeight: _weight(
                  userWeight: style.fontWeight,
                  emphasized: true,
                ),
              ),
            ),
          ),
          pw.Text(
            _money(receipt.total),
            style: pw.TextStyle(
              fontSize: s.grandTotal,
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Payment block
  // ---------------------------------------------------------------------------

  static pw.Widget _paymentBlock(
    Receipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    final double remaining = receipt.total - receipt.paidAmount;
    final double amountRemaining = remaining > 0 ? remaining : 0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _kvRow('طريقة الدفع', _paymentMethodLabel(receipt), s, style),
        _kvRow('المدفوع', _money(receipt.paidAmount), s, style),
        if (amountRemaining > 0)
          _kvRow(
            'المتبقي على العميل',
            _money(amountRemaining),
            s,
            style,
            emphasized: true,
          ),
        if (receipt.hasChange)
          _kvRow('الباقي للعميل', _money(receipt.change), s, style),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Balance block
  // ---------------------------------------------------------------------------

  static pw.Widget _balanceBlock(
    Receipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _kvRow(
          'الرصيد السابق',
          _money(receipt.previousBalance ?? 0),
          s,
          style,
        ),
        if (receipt.hasBalancePayment)
          _kvRow(
            'مدفوع على الرصيد السابق',
            _money(receipt.paidOnBalance),
            s,
            style,
          ),
        _kvRow(
          'الرصيد الحالي',
          _money(receipt.newBalance ?? 0),
          s,
          style,
          emphasized: true,
        ),
      ],
    );
  }

  static pw.Widget _kvRow(
    String label,
    String value,
    _Sizes s,
    PrintStyleSettings style, {
    bool emphasized = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: s.kvLabel,
                fontWeight: _weight(
                  userWeight: style.fontWeight,
                  emphasized: true,
                ),
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: emphasized ? s.kvValueLarge : s.kvValue,
              fontWeight: _weight(
                userWeight: style.fontWeight,
                emphasized: emphasized,
              ),
            ),
            textAlign: pw.TextAlign.left,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Footer
  // ---------------------------------------------------------------------------

  static pw.Widget _footer(
    Receipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Center(
      child: pw.Text(
        _footerText(receipt),
        style: pw.TextStyle(
          fontSize: s.footer,
          color: PdfColors.grey700,
          fontStyle: pw.FontStyle.italic,
          fontWeight: _weight(
            userWeight: style.fontWeight,
            emphasized: false,
          ),
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static String _footerText(Receipt receipt) {
    final String? custom = receipt.footer;
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }
    return _defaultFooter;
  }

  // ---------------------------------------------------------------------------
  // Dividers
  // ---------------------------------------------------------------------------

  static pw.Widget _divider({bool double = false}) {
    if (double) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          _singleRule(),
          pw.SizedBox(height: 2),
          _singleRule(),
        ],
      );
    }
    return _singleRule();
  }

  static pw.Widget _singleRule() => pw.Container(
        height: 0.6,
        color: PdfColors.grey600,
      );

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  static String _money(double value) {
    final String number;
    if (value == value.roundToDouble()) {
      number = _addThousandsSeparator(value.toInt().toString());
    } else {
      number = value.toStringAsFixed(2);
    }
    return '$number $_currency';
  }

  static String _qty(double value) {
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
    if (receipt.paidAmount <= 0) return 'آجل';
    if (receipt.paidAmount >= receipt.total) return 'نقدي';
    return 'نقدي (جزئي)';
  }
}

// ============================================================================
// Size profile
// ============================================================================

/// Bundle of font sizes and paddings for one paper format.
///
/// The `forSize` factory accepts an optional `scale` (from
/// [PrintStyleSettings]) that multiplies every size and padding field.
class _Sizes {
  const _Sizes({
    required this.companyName,
    required this.branchName,
    required this.title,
    required this.meta,
    required this.metaLabelWidth,
    required this.tableHeader,
    required this.tableRow,
    required this.rowNumWidth,
    required this.cellPadH,
    required this.cellPadV,
    required this.grandTotal,
    required this.kvLabel,
    required this.kvValue,
    required this.kvValueLarge,
    required this.footer,
    required this.sectionGap,
  });

  factory _Sizes.forSize(
    ReceiptPaperSize size, {
    double scale = 1.0,
  }) {
    final double s = scale.clamp(0.8, 1.6);
    switch (size) {
      case ReceiptPaperSize.mm58:
        return _Sizes(
          companyName: 12 * s,
          branchName: 8 * s,
          title: 9 * s,
          meta: 7.5 * s,
          metaLabelWidth: 62 * s,
          tableHeader: 7 * s,
          tableRow: 7 * s,
          rowNumWidth: 14 * s,
          cellPadH: 2.5 * s,
          cellPadV: 3 * s,
          grandTotal: 11 * s,
          kvLabel: 8 * s,
          kvValue: 8.5 * s,
          kvValueLarge: 10 * s,
          footer: 7 * s,
          sectionGap: 5 * s,
        );
      case ReceiptPaperSize.mm80:
        return _Sizes(
          companyName: 14 * s,
          branchName: 9 * s,
          title: 10 * s,
          meta: 8 * s,
          metaLabelWidth: 78 * s,
          tableHeader: 7.5 * s,
          tableRow: 7.5 * s,
          rowNumWidth: 16 * s,
          cellPadH: 3 * s,
          cellPadV: 3.5 * s,
          grandTotal: 12 * s,
          kvLabel: 8.5 * s,
          kvValue: 9.5 * s,
          kvValueLarge: 11 * s,
          footer: 8 * s,
          sectionGap: 6 * s,
        );
      case ReceiptPaperSize.a4:
        return _Sizes(
          companyName: 20 * s,
          branchName: 11 * s,
          title: 14 * s,
          meta: 10 * s,
          metaLabelWidth: 110 * s,
          tableHeader: 10 * s,
          tableRow: 10 * s,
          rowNumWidth: 24 * s,
          cellPadH: 6 * s,
          cellPadV: 6 * s,
          grandTotal: 16 * s,
          kvLabel: 11 * s,
          kvValue: 12 * s,
          kvValueLarge: 14 * s,
          footer: 10 * s,
          sectionGap: 10 * s,
        );
    }
  }

  final double companyName;
  final double branchName;
  final double title;
  final double meta;
  final double metaLabelWidth;
  final double tableHeader;
  final double tableRow;
  final double rowNumWidth;
  final double cellPadH;
  final double cellPadV;
  final double grandTotal;
  final double kvLabel;
  final double kvValue;
  final double kvValueLarge;
  final double footer;
  final double sectionGap;
}
