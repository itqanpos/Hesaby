// lib/features/purchases/data/services/pdf_purchase_receipt_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/printing/pdf_shared_components.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/purchase_receipt.dart';

/// Builds a PDF document from a [PurchaseReceipt].
///
/// **Phase P-1b:** accepts an optional [PrintStyleSettings].
/// **Phase U-5:** accepts optional [logoBytes] drawn centered at the top.
/// **Unified Template:** now uses `PdfSharedHeader`, `PdfSharedFooter`, and
/// `PdfSharedFormat` for visual consistency across the app.
abstract final class PdfPurchaseReceiptBuilder {
  static const String _currency = 'ج.م';
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
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  }) async {
    final pw.ThemeData theme = await PdfSharedFonts.loadTheme();

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
          style: style,
          logoBytes: logoBytes,
        ),
      ),
    );

    return document.save();
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  static List<pw.Widget> _buildContent({
    required PurchaseReceipt receipt,
    required ReceiptPaperSize paperSize,
    required PrintStyleSettings style,
    Uint8List? logoBytes,
  }) {
    final _Sizes s = _Sizes.forSize(paperSize, scale: style.fontScale);

    return <pw.Widget>[
      PdfSharedHeader.build(
        title: 'فاتورة مشتريات',
        companyName: receipt.companyName,
        branchName: receipt.branchName,
        style: style,
        logoBytes: logoBytes,
        logoWidth: s.logoWidth,
        // ✅ إرسال الحجم الأساسي (غير المُضاعف)
        titleFontSize: paperSize == ReceiptPaperSize.a4
            ? 14
            : (paperSize == ReceiptPaperSize.mm80 ? 10 : 9),
      ),
      pw.SizedBox(height: s.sectionGap),
      _metaBlock(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _divider(double: true),
      pw.SizedBox(height: s.sectionGap),
      _itemsTable(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _grandTotal(receipt, s, style),
      pw.SizedBox(height: s.sectionGap),
      _totalsBreakdown(receipt, s, style),
      if (receipt.hasSupplierContact) ...<pw.Widget>[
        pw.SizedBox(height: s.sectionGap),
        _divider(),
        pw.SizedBox(height: s.sectionGap),
        _supplierContact(receipt, s, style),
      ],
      if (receipt.hasNotes) ...<pw.Widget>[
        pw.SizedBox(height: s.sectionGap),
        _divider(),
        pw.SizedBox(height: s.sectionGap),
        _notesBlock(receipt, s, style),
      ],
      pw.SizedBox(height: s.sectionGap * 1.5),
      _divider(),
      pw.SizedBox(height: s.sectionGap),
      _footer(receipt, s, style),
    ];
  }

  // ---------------------------------------------------------------------------
  // Meta
  // ---------------------------------------------------------------------------

  static pw.Widget _metaBlock(
    PurchaseReceipt receipt,
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
          PdfSharedFormat.dayDate(receipt.purchaseDate),
          s,
          style,
        ),
        _metaRow('المورد', receipt.supplierName, s, style),
        _metaRow('الحالة', _statusLabel(receipt.status), s, style),
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
              PdfSharedFormat.norm('$label:'),
              style: pw.TextStyle(
                fontSize: s.meta,
                fontWeight:
                    PdfSharedStyle.weight(style, emphasized: true),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              PdfSharedFormat.norm(value),
              style: pw.TextStyle(
                fontSize: s.meta,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: emphasized),
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
    PurchaseReceipt receipt,
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
        decoration: PdfSharedTable.headerDecoration,
        children: <pw.Widget>[
          _cell('الإجمالي',
              fontSize: s.tableHeader,
              emphasized: true,
              center: true,
              s: s,
              style: style),
          _cell('التكلفة',
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
      final PurchaseReceiptLine line = receipt.lines[i];
      rows.add(
        pw.TableRow(
          decoration: PdfSharedTable.zebraDecoration(i.isOdd),
          children: <pw.Widget>[
            _cell(_money(line.lineTotal),
                fontSize: s.tableRow,
                emphasized: true,
                center: true,
                s: s,
                style: style),
            _cell(_money(line.unitCost),
                fontSize: s.tableRow,
                center: true,
                s: s,
                style: style),
            _cell('${PdfSharedFormat.quantity(line.quantity)} ${line.unitName}',
                fontSize: s.tableRow,
                center: true,
                s: s,
                style: style),
            _cell(line.productName,
                fontSize: s.tableRow, s: s, style: style),
            _cell('${i + 1}',
                fontSize: s.tableRow,
                center: true,
                s: s,
                style: style),
          ],
        ),
      );
    }

    rows.add(
      pw.TableRow(
        decoration: PdfSharedTable.totalsDecoration,
        children: <pw.Widget>[
          _cell(_money(receipt.subtotal),
              fontSize: s.tableRow,
              emphasized: true,
              center: true,
              s: s,
              style: style),
          _cell('', fontSize: s.tableRow, s: s, style: style),
          _cell('${receipt.lines.length}',
              fontSize: s.tableRow,
              center: true,
              s: s,
              style: style),
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
      border: PdfSharedTable.border,
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
        PdfSharedFormat.norm(text),
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: PdfSharedStyle.weight(style,
              emphasized: emphasized),
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
    PurchaseReceipt receipt,
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
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              'إجمالي الفاتورة',
              style: pw.TextStyle(
                fontSize: s.grandTotal,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: true),
              ),
            ),
          ),
          pw.Text(
            _money(receipt.total),
            style: pw.TextStyle(
              fontSize: s.grandTotal,
              fontWeight: PdfSharedStyle.weight(style,
                  emphasized: true),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Totals breakdown
  // ---------------------------------------------------------------------------

  static pw.Widget _totalsBreakdown(
    PurchaseReceipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _kvRow('المجموع الفرعي', _money(receipt.subtotal), s, style),
        if (receipt.hasDiscount)
          _kvRow('الخصم', _money(receipt.discount), s, style),
        if (receipt.hasTax)
          _kvRow('الضريبة', _money(receipt.taxAmount), s, style),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Supplier contact
  // ---------------------------------------------------------------------------

  static pw.Widget _supplierContact(
    PurchaseReceipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Text(
          'بيانات المورد',
          style: pw.TextStyle(
            fontSize: s.kvLabel,
            fontWeight:
                PdfSharedStyle.weight(style, emphasized: true),
          ),
        ),
        pw.SizedBox(height: 4),
        if (receipt.supplierPhone != null &&
            receipt.supplierPhone!.trim().isNotEmpty)
          _kvRow('الهاتف', receipt.supplierPhone!, s, style),
        if (receipt.supplierEmail != null &&
            receipt.supplierEmail!.trim().isNotEmpty)
          _kvRow('البريد', receipt.supplierEmail!, s, style),
        if (receipt.hasSupplierAddress)
          _kvRow('العنوان', receipt.supplierAddress!, s, style),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Notes
  // ---------------------------------------------------------------------------

  static pw.Widget _notesBlock(
    PurchaseReceipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        pw.Text(
          'ملاحظات',
          style: pw.TextStyle(
            fontSize: s.kvLabel,
            fontWeight:
                PdfSharedStyle.weight(style, emphasized: true),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          PdfSharedFormat.norm(receipt.notes!),
          style: pw.TextStyle(
            fontSize: s.kvValue,
            fontWeight: PdfSharedStyle.weight(style,
                emphasized: false),
          ),
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
              PdfSharedFormat.norm(label),
              style: pw.TextStyle(
                fontSize: s.kvLabel,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: true),
              ),
            ),
          ),
          pw.Text(
            PdfSharedFormat.norm(value),
            style: pw.TextStyle(
              fontSize: emphasized ? s.kvValueLarge : s.kvValue,
              fontWeight: PdfSharedStyle.weight(style,
                  emphasized: emphasized),
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
    PurchaseReceipt receipt,
    _Sizes s,
    PrintStyleSettings style,
  ) {
    return pw.Center(
      child: pw.Text(
        PdfSharedFormat.norm(_footerText(receipt)),
        style: pw.TextStyle(
          fontSize: s.footer,
          color: PdfColors.grey700,
          fontStyle: pw.FontStyle.italic,
          fontWeight:
              PdfSharedStyle.weight(style, emphasized: false),
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
    return PdfSharedFooter.defaultThankYou;
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

  static String _money(double value) =>
      PdfSharedFormat.money(value, currency: _currency);

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
    required this.logoWidth,
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
          logoWidth: 70,
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
          logoWidth: 100,
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
          logoWidth: 130,
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
  final double logoWidth;
}
