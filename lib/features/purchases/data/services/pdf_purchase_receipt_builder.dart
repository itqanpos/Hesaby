// lib/features/purchases/data/services/pdf_purchase_receipt_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../domain/entities/purchase_receipt.dart';

/// Builds a PDF document from a [PurchaseReceipt].
///
/// Layout mirrors `PdfReceiptBuilder` (POS sale receipt) visually so the two
/// documents are consistent when printed side by side:
/// * Centred company name + branch.
/// * Boxed title "فاتورة مشتريات".
/// * Info block (invoice #, date, supplier, status).
/// * Bordered 5-column items table (الإجمالي / التكلفة / الكمية / الصنف / م).
/// * Grand-total band, then subtotal / discount / tax breakdown.
/// * Optional supplier contact and notes.
/// * Custom footer from `company_settings.receipt_footer`.
abstract final class PdfPurchaseReceiptBuilder {
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

  static const double _thermalFixedMm = 130;
  static const double _thermalPerLineMm = 14;

  static double _thermalHeightFor(int lineCount) {
    final double estimatedMm =
        _thermalFixedMm + lineCount * _thermalPerLineMm;
    final double clampedMm = estimatedMm.clamp(180.0, 420.0);
    return clampedMm * PdfPageFormat.mm;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static Future<Uint8List> build({
    required PurchaseReceipt receipt,
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
      title: receipt.invoiceNumber ?? 'شراء-${receipt.purchaseId}',
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
    required PurchaseReceipt receipt,
    required ReceiptPaperSize paperSize,
  }) {
    final _Sizes s = _Sizes.forSize(paperSize);

    return <pw.Widget>[
      _header(receipt, s),
      pw.SizedBox(height: s.sectionGap),
      _metaBlock(receipt, s),
      pw.SizedBox(height: s.sectionGap),
      _divider(double: true),
      pw.SizedBox(height: s.sectionGap),
      _itemsTable(receipt, s),
      pw.SizedBox(height: s.sectionGap),
      _grandTotal(receipt, s),
      pw.SizedBox(height: s.sectionGap),
      _totalsBreakdown(receipt, s),
      if (receipt.hasSupplierContact) ...<pw.Widget>[
        pw.SizedBox(height: s.sectionGap),
        _divider(),
        pw.SizedBox(height: s.sectionGap),
        _supplierContact(receipt, s),
      ],
      if (receipt.hasNotes) ...<pw.Widget>[
        pw.SizedBox(height: s.sectionGap),
        _divider(),
        pw.SizedBox(height: s.sectionGap),
        _notesBlock(receipt, s),
      ],
      pw.SizedBox(height: s.sectionGap * 1.5),
      _divider(),
      pw.SizedBox(height: s.sectionGap),
      _footer(receipt, s),
    ];
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  static pw.Widget _header(PurchaseReceipt receipt, _Sizes s) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Center(
          child: pw.Text(
            receipt.companyName,
            style: pw.TextStyle(
              fontSize: s.companyName,
              fontWeight: pw.FontWeight.bold,
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
              border: pw.Border.all(
                color: PdfColors.black,
                width: 1,
              ),
              borderRadius: const pw.BorderRadius.all(
                pw.Radius.circular(3),
              ),
            ),
            child: pw.Text(
              'فاتورة مشتريات',
              style: pw.TextStyle(
                fontSize: s.title,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Meta
  // ---------------------------------------------------------------------------

  static pw.Widget _metaBlock(PurchaseReceipt receipt, _Sizes s) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _metaRow(
          'رقم الفاتورة',
          receipt.invoiceNumber ?? '—',
          s,
          boldValue: true,
        ),
        _metaRow(
          'التاريخ',
          _formatDayAndDate(receipt.purchaseDate),
          s,
        ),
        _metaRow('المورد', receipt.supplierName, s),
        _metaRow('الحالة', _statusLabel(receipt.status), s),
      ],
    );
  }

  static pw.Widget _metaRow(
    String label,
    String value,
    _Sizes s, {
    bool boldValue = false,
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
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: s.meta,
                fontWeight: boldValue
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
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

  static pw.Widget _itemsTable(PurchaseReceipt receipt, _Sizes s) {
    final Map<int, pw.TableColumnWidth> columnWidths =
        <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(1.4), // الإجمالي
      1: pw.FlexColumnWidth(1.2), // التكلفة
      2: pw.FlexColumnWidth(1.3), // الكمية
      3: pw.FlexColumnWidth(3.0), // الصنف
      4: pw.FixedColumnWidth(s.rowNumWidth), // م
    };

    final List<pw.TableRow> rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: <pw.Widget>[
          _cell('الإجمالي',
              fontSize: s.tableHeader, bold: true, center: true, s: s),
          _cell('التكلفة',
              fontSize: s.tableHeader, bold: true, center: true, s: s),
          _cell('الكمية',
              fontSize: s.tableHeader, bold: true, center: true, s: s),
          _cell('الصنف',
              fontSize: s.tableHeader, bold: true, s: s),
          _cell('م',
              fontSize: s.tableHeader, bold: true, center: true, s: s),
        ],
      ),
    ];

    for (int i = 0; i < receipt.lines.length; i++) {
      final bool zebra = i.isOdd;
      final PurchaseReceiptLine line = receipt.lines[i];
      rows.add(
        pw.TableRow(
          decoration: zebra
              ? const pw.BoxDecoration(color: PdfColors.grey100)
              : null,
          children: <pw.Widget>[
            _cell(_money(line.lineTotal),
                fontSize: s.tableRow, bold: true, center: true, s: s),
            _cell(_money(line.unitCost),
                fontSize: s.tableRow, center: true, s: s),
            _cell('${_qty(line.quantity)} ${line.unitName}',
                fontSize: s.tableRow, center: true, s: s),
            _cell(line.productName, fontSize: s.tableRow, s: s),
            _cell('${i + 1}',
                fontSize: s.tableRow, center: true, s: s),
          ],
        ),
      );
    }

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: <pw.Widget>[
          _cell(_money(receipt.subtotal),
              fontSize: s.tableRow, bold: true, center: true, s: s),
          _cell('', fontSize: s.tableRow, s: s),
          _cell('${receipt.lines.length}',
              fontSize: s.tableRow, center: true, s: s),
          _cell('المجموع الفرعي',
              fontSize: s.tableRow, bold: true, s: s),
          _cell('', fontSize: s.tableRow, s: s),
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
    bool bold = false,
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
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.right,
        softWrap: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Grand total
  // ---------------------------------------------------------------------------

  static pw.Widget _grandTotal(PurchaseReceipt receipt, _Sizes s) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(
        horizontal: s.cellPadH * 2,
        vertical: s.cellPadV * 1.5,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              'إجمالي الفاتورة',
              style: pw.TextStyle(
                fontSize: s.grandTotal,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(
            _money(receipt.total),
            style: pw.TextStyle(
              fontSize: s.grandTotal,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Totals breakdown
  // ---------------------------------------------------------------------------

  static pw.Widget _totalsBreakdown(PurchaseReceipt receipt, _Sizes s) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _kvRow('المجموع الفرعي', _money(receipt.subtotal), s),
        if (receipt.hasDiscount)
          _kvRow('الخصم', _money(receipt.discount), s),
        if (receipt.hasTax)
          _kvRow('الضريبة', _money(receipt.taxAmount), s),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Supplier contact
  // ---------------------------------------------------------------------------

  static pw.Widget _supplierContact(PurchaseReceipt receipt, _Sizes s) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Text(
          'بيانات المورد',
          style: pw.TextStyle(
            fontSize: s.kvLabel,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        if (receipt.supplierPhone != null &&
            receipt.supplierPhone!.trim().isNotEmpty)
          _kvRow('الهاتف', receipt.supplierPhone!, s),
        if (receipt.supplierEmail != null &&
            receipt.supplierEmail!.trim().isNotEmpty)
          _kvRow('البريد', receipt.supplierEmail!, s),
        if (receipt.hasSupplierAddress)
          _kvRow('العنوان', receipt.supplierAddress!, s),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Notes
  // ---------------------------------------------------------------------------

  static pw.Widget _notesBlock(PurchaseReceipt receipt, _Sizes s) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Text(
          'ملاحظات',
          style: pw.TextStyle(
            fontSize: s.kvLabel,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          receipt.notes!,
          style: pw.TextStyle(fontSize: s.kvValue),
          softWrap: true,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // KV row
  // ---------------------------------------------------------------------------

  static pw.Widget _kvRow(
    String label,
    String value,
    _Sizes s, {
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
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: emphasized ? s.kvValueLarge : s.kvValue,
              fontWeight:
                  emphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
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

  static pw.Widget _footer(PurchaseReceipt receipt, _Sizes s) {
    return pw.Center(
      child: pw.Text(
        _footerText(receipt),
        style: pw.TextStyle(
          fontSize: s.footer,
          color: PdfColors.grey700,
          fontStyle: pw.FontStyle.italic,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static String _footerText(PurchaseReceipt receipt) {
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
      number = _thousands(value.toInt().toString());
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

  static String _thousands(String intStr) {
    final bool neg = intStr.startsWith('-');
    final String digits = neg ? intStr.substring(1) : intStr;
    final StringBuffer buf = StringBuffer();
    if (neg) buf.write('-');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  /// Returns `"الأحد  2026/10/09  02:55 م"`.
  static String _formatDayAndDate(DateTime value) {
    final DateTime local = value.toLocal();
    final int wd = local.weekday;
    final String day = _arabicDays[(wd - 1).clamp(0, 6)];
    final String y = local.year.toString().padLeft(4, '0');
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    final int h24 = local.hour;
    final int h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final String ampm = h24 >= 12 ? 'م' : 'ص';
    final String hh = h12.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    return '$day  $y/$m/$d  $hh:$mm $ampm';
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'مسودة';
      case 'confirmed':
        return 'مؤكدة';
      case 'cancelled':
        return 'ملغاة';
      default:
        return status;
    }
  }
}

// ============================================================================
// Size profile
// ============================================================================

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

  factory _Sizes.forSize(ReceiptPaperSize size) {
    switch (size) {
      case ReceiptPaperSize.mm58:
        return const _Sizes(
          companyName: 12,
          branchName: 8,
          title: 9,
          meta: 7.5,
          metaLabelWidth: 62,
          tableHeader: 7,
          tableRow: 7,
          rowNumWidth: 14,
          cellPadH: 2.5,
          cellPadV: 3,
          grandTotal: 11,
          kvLabel: 8,
          kvValue: 8.5,
          kvValueLarge: 10,
          footer: 7,
          sectionGap: 5,
        );
      case ReceiptPaperSize.mm80:
        return const _Sizes(
          companyName: 14,
          branchName: 9,
          title: 10,
          meta: 8,
          metaLabelWidth: 78,
          tableHeader: 7.5,
          tableRow: 7.5,
          rowNumWidth: 16,
          cellPadH: 3,
          cellPadV: 3.5,
          grandTotal: 12,
          kvLabel: 8.5,
          kvValue: 9.5,
          kvValueLarge: 11,
          footer: 8,
          sectionGap: 6,
        );
      case ReceiptPaperSize.a4:
        return const _Sizes(
          companyName: 20,
          branchName: 11,
          title: 14,
          meta: 10,
          metaLabelWidth: 110,
          tableHeader: 10,
          tableRow: 10,
          rowNumWidth: 24,
          cellPadH: 6,
          cellPadV: 6,
          grandTotal: 16,
          kvLabel: 11,
          kvValue: 12,
          kvValueLarge: 14,
          footer: 10,
          sectionGap: 10,
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
