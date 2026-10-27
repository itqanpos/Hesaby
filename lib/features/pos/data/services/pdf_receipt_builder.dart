// lib/features/pos/data/services/pdf_receipt_builder.dart

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/printing/pdf_shared_components.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/receipt_number_format.dart';

enum ReceiptPaperSize { mm58, mm80, a4 }

abstract final class PdfReceiptBuilder {
  static const String _currency = 'ج.م';

  static double _thermalHeightFor(int lineCount) {
    // مساحة ثابتة 250mm + 15mm لكل سطر
    final double estimatedMm = 250 + (lineCount * 15);
    return estimatedMm.clamp(250.0, 3000.0) * PdfPageFormat.mm;
  }

  static Future<Uint8List> build({
    required Receipt receipt,
    required ReceiptPaperSize size,
    PrintStyleSettings style = const PrintStyleSettings.defaults(),
    Uint8List? logoBytes,
  }) async {
    final pw.ThemeData theme = await PdfSharedFonts.loadTheme();

    final PdfPageFormat pageFormat;
    final double padding;
    switch (size) {
      case ReceiptPaperSize.mm58:
        pageFormat = PdfPageFormat(58 * PdfPageFormat.mm,
            _thermalHeightFor(receipt.lines.length),
            marginAll: 0);
        padding = 4;
      case ReceiptPaperSize.mm80:
        pageFormat = PdfPageFormat(80 * PdfPageFormat.mm,
            _thermalHeightFor(receipt.lines.length),
            marginAll: 0);
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

    if (size == ReceiptPaperSize.a4) {
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
    } else {
      // حراري: صفحة واحدة فقط
      document.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(padding),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: _buildContent(
              receipt: receipt,
              paperSize: size,
              style: style,
              logoBytes: logoBytes,
            ),
          ),
        ),
      );
    }

    return document.save();
  }

  static List<pw.Widget> _buildContent({
    required Receipt receipt,
    required ReceiptPaperSize paperSize,
    required PrintStyleSettings style,
    Uint8List? logoBytes,
  }) {
    final _Sizes s = _Sizes.forSize(paperSize, scale: style.fontScale);

    final double logoWidth = paperSize == ReceiptPaperSize.a4
        ? 160
        : (paperSize == ReceiptPaperSize.mm80 ? 80 : 60);
    final double titleBase = paperSize == ReceiptPaperSize.a4 ? 16.0 : 12.0;

    return <pw.Widget>[
      PdfSharedHeader.build(
        title: 'فاتورة مبيعات',
        companyName: receipt.companyName,
        branchName: receipt.branchName,
        address: receipt.companyAddress,
        phone: receipt.companyPhone,
        taxNumber: receipt.hasTaxNumberToPrint
            ? receipt.companyTaxNumber
            : null,
        commercialRegister: receipt.hasCommercialRegisterToPrint
            ? receipt.companyCommercialRegister
            : null,
        style: style,
        logoBytes: logoBytes,
        logoWidth: logoWidth,
        titleFontSize: titleBase,
      ),
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

  static pw.Widget _metaBlock(
      Receipt receipt, _Sizes s, PrintStyleSettings style) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _metaRow('رقم الفاتورة', receipt.invoiceNumber ?? '—', s, style,
            emphasized: true),
        _metaRow('التاريخ', PdfSharedFormat.dayDate(receipt.dateTime), s, style),
        if (receipt.cashierName != null &&
            receipt.cashierName!.trim().isNotEmpty)
          _metaRow('الكاشير', receipt.cashierName!, s, style),
        if (receipt.hasCustomer) ...<pw.Widget>[
          _metaRow('العميل', receipt.customerName!, s, style),
          if (receipt.hasCustomerAddress)
            _metaRow('عنوان العميل', receipt.customerAddress!, s, style),
          if (receipt.hasCustomerPhone)
            _metaRow('هاتف العميل', receipt.customerPhone!, s, style),
        ],
      ],
    );
  }

  static pw.Widget _metaRow(
      String label, String value, _Sizes s, PrintStyleSettings style,
      {bool emphasized = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          // عرض ثابت للعنوان (مثل: رقم الفاتورة) يمنع تداخله مع القيمة
          pw.SizedBox(
            width: s.metaLabelWidth,
            child: pw.Text(
              PdfSharedFormat.norm('$label:'),
              style: pw.TextStyle(
                fontSize: s.meta,
                fontWeight: PdfSharedStyle.weight(style, emphasized: true),
              ),
              textAlign: pw.TextAlign.right,
              maxLines: 1, // يمنع نزول العنوان لسطرين
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Text(
              PdfSharedFormat.norm(value),
              style: pw.TextStyle(
                fontSize: s.meta,
                fontWeight:
                    PdfSharedStyle.weight(style, emphasized: emphasized),
              ),
              textAlign: pw.TextAlign.left,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _itemsTable(
      Receipt receipt, _Sizes s, PrintStyleSettings style) {
    // ✅ توزيع أعمدة ذكي: إعطاء مساحة أكبر للصنف، وتصغير "م"
    final Map<int, pw.TableColumnWidth> columnWidths =
        <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(1.3), // الإجمالي
      1: pw.FlexColumnWidth(1.1), // السعر
      2: pw.FlexColumnWidth(1.1), // الكمية
      3: pw.FlexColumnWidth(2.5), // الصنف (أكبر مساحة)
      4: pw.FixedColumnWidth(12), // م (مساحة صغيرة)
    };

    double totalQuantity = 0;
    for (final line in receipt.lines) {
      totalQuantity += line.quantity;
    }

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
      final ReceiptLine line = receipt.lines[i];
      rows.add(
        pw.TableRow(
          decoration: PdfSharedTable.zebraDecoration(i.isOdd),
          children: <pw.Widget>[
            _cell(_money(line.lineTotal, receipt),
                fontSize: s.tableRow,
                emphasized: true,
                center: true,
                s: s,
                style: style),
            _cell(_money(line.unitPrice, receipt),
                fontSize: s.tableRow, center: true, s: s, style: style),
            _cell('${PdfSharedFormat.quantity(line.quantity)} ${line.unitName}',
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
        decoration: PdfSharedTable.totalsDecoration,
        children: <pw.Widget>[
          _cell(_money(receipt.subtotal, receipt),
              fontSize: s.tableRow,
              emphasized: true,
              center: true,
              s: s,
              style: style),
          _cell('', fontSize: s.tableRow, s: s, style: style),
          _cell(PdfSharedFormat.quantity(totalQuantity),
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

    if (receipt.hasDiscountToPrint) {
      rows.add(_summaryRow(
          'الخصم', '- ${_money(receipt.discount, receipt)}', s, style));
    }
    if (receipt.hasTaxToPrint) {
      rows.add(_summaryRow(
          'الضريبة', _money(receipt.taxAmount, receipt), s, style));
    }

    return pw.Table(
      border: PdfSharedTable.border,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: columnWidths,
      children: rows,
    );
  }

  static pw.TableRow _summaryRow(
      String label, String value, _Sizes s, PrintStyleSettings style) {
    return pw.TableRow(
      children: <pw.Widget>[
        _cell(value,
            fontSize: s.tableRow,
            emphasized: true,
            center: true,
            s: s,
            style: style),
        _cell('', fontSize: s.tableRow, s: s, style: style),
        _cell('', fontSize: s.tableRow, s: s, style: style),
        _cell(label,
            fontSize: s.tableRow, emphasized: true, s: s, style: style),
        _cell('', fontSize: s.tableRow, s: s, style: style),
      ],
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
    // ✅ استخدام FittedBox لمنع كسر الكلمات في الأعمدة الضيقة
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
          horizontal: s.cellPadH, vertical: s.cellPadV),
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: center ? pw.Alignment.center : pw.Alignment.centerRight,
        child: pw.Text(
          PdfSharedFormat.norm(text),
          style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight:
                  PdfSharedStyle.weight(style, emphasized: emphasized)),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.right,
          maxLines: 1,
        ),
      ),
    );
  }

  static pw.Widget _totalsSection(
      Receipt receipt, _Sizes s, PrintStyleSettings style) {
    final double totalOwed = receipt.total + (receipt.previousBalance ?? 0);
    final double newBalance = receipt.newBalance ?? 0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        _kvRow('الإجمالي الحالي', _money(receipt.total, receipt), s, style),
        if (receipt.hasCustomer &&
            (receipt.previousBalance ?? 0) != 0) ...<pw.Widget>[
          pw.SizedBox(height: 6),
          _kvRow('الرصيد السابق',
              _money(receipt.previousBalance!.abs(), receipt), s, style),
        ],
        pw.SizedBox(height: 8),
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
              horizontal: s.cellPadH * 2, vertical: s.cellPadV * 1.5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1.2),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  ((receipt.previousBalance ?? 0) != 0)
                      ? 'الإجمالي الكلي'
                      : 'إجمالي الفاتورة',
                  style: pw.TextStyle(
                      fontSize: s.grandTotal,
                      fontWeight:
                          PdfSharedStyle.weight(style, emphasized: true)),
                ),
              ),
              pw.Text(
                _money(totalOwed, receipt),
                style: pw.TextStyle(
                    fontSize: s.grandTotal,
                    fontWeight:
                        PdfSharedStyle.weight(style, emphasized: true)),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        _kvRow('طريقة الدفع', _paymentMethodLabel(receipt), s, style),
        pw.SizedBox(height: 6),
        _kvRow('المدفوع', _money(receipt.paidAmount, receipt), s, style),
        if (receipt.hasBalanceChange) ...<pw.Widget>[
          pw.SizedBox(height: 8),
          _divider(),
          pw.SizedBox(height: 8),
          if (newBalance > 0)
            _kvRow('الرصيد الجديد على العميل', _money(newBalance, receipt), s,
                style,
                emphasized: true)
          else if (newBalance < 0)
            _kvRow('الرصيد الجديد (له عندنا)',
                _money(newBalance.abs(), receipt), s, style,
                emphasized: true)
          else
            _kvRow('الرصيد الجديد', _money(0, receipt), s, style,
                emphasized: true),
        ],
      ],
    );
  }

  static pw.Widget _kvRow(
      String label, String value, _Sizes s, PrintStyleSettings style,
      {bool emphasized = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              PdfSharedFormat.norm(label),
              style: pw.TextStyle(
                  fontSize: s.kvLabel,
                  fontWeight:
                      PdfSharedStyle.weight(style, emphasized: true)),
            ),
          ),
          pw.Text(
            PdfSharedFormat.norm(value),
            style: pw.TextStyle(
                fontSize: emphasized ? s.kvValueLarge : s.kvValue,
                fontWeight: PdfSharedStyle.weight(style,
                    emphasized: emphasized)),
            textAlign: pw.TextAlign.left,
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(
      Receipt receipt, _Sizes s, PrintStyleSettings style) {
    return pw.Center(
      child: pw.Text(
        PdfSharedFormat.norm(_footerText(receipt)),
        style: pw.TextStyle(
            fontSize: s.footer,
            color: PdfColors.grey700,
            fontStyle: pw.FontStyle.italic,
            fontWeight:
                PdfSharedStyle.weight(style, emphasized: false)),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static String _footerText(Receipt receipt) {
    final String? custom = receipt.footer;
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return PdfSharedFooter.defaultThankYou;
  }

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

  static pw.Widget _singleRule() =>
      pw.Container(height: 0.6, color: PdfColors.grey600);

  static String _money(double value, Receipt receipt) {
    final String symbol = receipt.showCurrencySymbol ? _currency : '';
    return ReceiptNumberFormat.money(value, currency: symbol);
  }

  static String _paymentMethodLabel(Receipt receipt) {
    if (receipt.paidAmount <= 0) return 'آجل';
    if (receipt.paidAmount >= receipt.total) return 'نقدي';
    return 'نقدي (جزئي)';
  }
}

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

  factory _Sizes.forSize(ReceiptPaperSize size, {double scale = 1.0}) {
    // 🚀 السر هنا: نقص أقصى تكبير للورق الحراري إلى 1.1 (بدلاً من 1.6)
    // حتى لا تنفجر النصوص وتنكسر الكلمات. الـ A4 يظل مسموحاً له بالتكبير.
    final double effectiveScale = size == ReceiptPaperSize.a4 
        ? scale.clamp(0.8, 1.6) 
        : scale.clamp(0.8, 1.1);

    switch (size) {
      case ReceiptPaperSize.mm58:
        return _Sizes(
          companyName: 14 * effectiveScale,
          branchName: 9 * effectiveScale,
          title: 11 * effectiveScale,
          meta: 8 * effectiveScale, // تقليل حجم الميتا
          metaLabelWidth: 55 * effectiveScale, // تقليل عرض العنوان
          tableHeader: 8 * effectiveScale, // تقليل حجم رأس الجدول
          tableRow: 8 * effectiveScale,
          rowNumWidth: 16 * effectiveScale,
          cellPadH: 2 * effectiveScale,
          cellPadV: 3 * effectiveScale,
          grandTotal: 13 * effectiveScale,
          kvLabel: 9 * effectiveScale,
          kvValue: 9 * effectiveScale,
          kvValueLarge: 11 * effectiveScale,
          footer: 8 * effectiveScale,
          sectionGap: 6 * effectiveScale,
          logoWidth: 60,
        );
      case ReceiptPaperSize.mm80:
        return _Sizes(
          companyName: 16 * effectiveScale,
          branchName: 10 * effectiveScale,
          title: 12 * effectiveScale,
          meta: 9 * effectiveScale, // 9 بدلاً من 9.5
          metaLabelWidth: 65 * effectiveScale, // 65 بدلاً من 85 لمنع الكسر
          tableHeader: 8.5 * effectiveScale, // 8.5 بدلاً من 9
          tableRow: 9 * effectiveScale,
          rowNumWidth: 18 * effectiveScale,
          cellPadH: 2.5 * effectiveScale, // تقليل الحواف
          cellPadV: 3.5 * effectiveScale,
          grandTotal: 14 * effectiveScale,
          kvLabel: 9.5 * effectiveScale,
          kvValue: 10 * effectiveScale,
          kvValueLarge: 12 * effectiveScale,
          footer: 9 * effectiveScale,
          sectionGap: 6 * effectiveScale,
          logoWidth: 80,
        );
      case ReceiptPaperSize.a4:
        return _Sizes(
          companyName: 22 * effectiveScale,
          branchName: 12 * effectiveScale,
          title: 16 * effectiveScale,
          meta: 11 * effectiveScale,
          metaLabelWidth: 120 * effectiveScale,
          tableHeader: 11 * effectiveScale,
          tableRow: 11 * effectiveScale,
          rowNumWidth: 26 * effectiveScale,
          cellPadH: 7 * effectiveScale,
          cellPadV: 7 * effectiveScale,
          grandTotal: 18 * effectiveScale,
          kvLabel: 12 * effectiveScale,
          kvValue: 13 * effectiveScale,
          kvValueLarge: 15 * effectiveScale,
          footer: 11 * effectiveScale,
          sectionGap: 11 * effectiveScale,
          logoWidth: 180,
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
