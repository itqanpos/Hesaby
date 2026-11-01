// lib/features/pos/data/services/esc_pos_receipt_builder.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:google_fonts/google_fonts.dart';

import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/receipt_number_format.dart';

abstract final class EscPosReceiptBuilder {
  static const List<int> _init = <int>[0x1B, 0x40];
  static const List<int> _feedAndCut = <int>[
    0x1B, 0x64, 0x04,
    0x1D, 0x56, 0x42, 0x00,
  ];

  static const int widthMm80 = 576;
  static const int widthMm58 = 384;

  static String? _regularFamily;
  static String? _boldFamily;
  static String? _mediumFamily;

  static Future<List<int>> build({
    required Receipt receipt,
    int paperWidthDots = widthMm80,
    Uint8List? logoBytes,
    double fontScale = 1.0,
    PrintFontWeight fontWeight = PrintFontWeight.normal,
  }) async {
    final ui.Image image = await renderToImage(
      receipt: receipt,
      paperWidthDots: paperWidthDots,
      logoBytes: logoBytes,
      fontScale: fontScale,
      fontWeight: fontWeight,
    );

    final List<int> raster = await _encodeRaster(image);
    image.dispose();

    return <int>[..._init, ...raster, ..._feedAndCut];
  }

  static Future<ui.Image> renderToImage({
    required Receipt receipt,
    int paperWidthDots = widthMm80,
    Uint8List? logoBytes,
    double fontScale = 1.0,
    PrintFontWeight fontWeight = PrintFontWeight.normal,
  }) async {
    await _ensureFonts();

    final double clampedScale =
        fontScale.clamp(kMinPrintFontScale, kMaxPrintFontScale);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);

    final _Painter painter = _Painter(
      canvas: canvas,
      paperWidthDots: paperWidthDots,
      regularFamily: _regularFamily!,
      boldFamily: _boldFamily!,
      mediumFamily: _mediumFamily ?? _regularFamily!,
      fontScale: clampedScale,
      baseWeight: fontWeight,
    );
    await painter.paint(receipt, logoBytes);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(
      paperWidthDots,
      painter.totalHeight.ceil(),
    );
    picture.dispose();
    return image;
  }

  static const String _bundledRegular = 'CairoReceipt';
  static const String _bundledBold = 'CairoReceiptBold';

  static Future<bool> _loadBundledFonts() async {
    try {
      final ByteData regular =
          await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final ByteData bold =
          await rootBundle.load('assets/fonts/Cairo-Bold.ttf');

      final FontLoader regularLoader = FontLoader(_bundledRegular)
        ..addFont(Future<ByteData>.value(regular));
      final FontLoader boldLoader = FontLoader(_bundledBold)
        ..addFont(Future<ByteData>.value(bold));
      await regularLoader.load();
      await boldLoader.load();

      _regularFamily = _bundledRegular;
      _mediumFamily = _bundledRegular;
      _boldFamily = _bundledBold;
      return true;
    } on Object {
      return false;
    }
  }

  static Future<void> _ensureFonts() async {
    if (_regularFamily != null && _boldFamily != null) return;

    if (await _loadBundledFonts()) return;

    final TextStyle regular = GoogleFonts.cairo();
    final TextStyle medium = GoogleFonts.cairo(fontWeight: FontWeight.w600);
    final TextStyle bold = GoogleFonts.cairo(fontWeight: FontWeight.w700);

    await GoogleFonts.pendingFonts(<TextStyle>[regular, medium, bold]);

    _regularFamily = regular.fontFamily ?? 'Cairo';
    _mediumFamily = medium.fontFamily ?? 'Cairo';
    _boldFamily = bold.fontFamily ?? 'Cairo';
  }

  static Future<List<int>> _encodeRaster(ui.Image image) async {
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw StateError('Failed to read pixel data from the receipt image.');
    }

    final Uint8List pixels = byteData.buffer.asUint8List();
    final int width = image.width;
    final int height = image.height;
    final int widthBytes = (width + 7) ~/ 8;

    final List<double> gray = List<double>.filled(width * height, 255);
    for (int y = 0; y < height; y++) {
      final int rowStart = y * width * 4;
      for (int x = 0; x < width; x++) {
        final int idx = rowStart + x * 4;
        final int a = pixels[idx + 3];
        final int r = pixels[idx];
        final int g = pixels[idx + 1];
        final int b = pixels[idx + 2];
        final double lum = (r * 299 + g * 587 + b * 114) / 1000.0;
        gray[y * width + x] = a < 128 ? 255.0 : lum;
      }
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int i = y * width + x;
        final double oldVal = gray[i];
        final double newVal = oldVal < 128 ? 0.0 : 255.0;
        gray[i] = newVal;
        final double err = oldVal - newVal;
        if (x + 1 < width) gray[i + 1] += err * 7 / 16;
        if (y + 1 < height) {
          if (x > 0) gray[i + width - 1] += err * 3 / 16;
          gray[i + width] += err * 5 / 16;
          if (x + 1 < width) gray[i + width + 1] += err * 1 / 16;
        }
      }
    }

    final Uint8List raster = Uint8List(widthBytes * height);
    int offset = 0;
    for (int y = 0; y < height; y++) {
      final int rowStart = y * width;
      for (int bx = 0; bx < widthBytes; bx++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final int x = bx * 8 + bit;
          if (x >= width) break;
          if (gray[rowStart + x] < 128) byte |= 0x80 >> bit;
        }
        raster[offset++] = byte;
      }
    }

    return <int>[
      0x1D, 0x76, 0x30, 0x00,
      widthBytes & 0xFF,
      (widthBytes >> 8) & 0xFF,
      height & 0xFF,
      (height >> 8) & 0xFF,
      ...raster,
    ];
  }
}

// ============================================================================
// Painter
// ============================================================================

class _Painter {
  _Painter({
    required this.canvas,
    required this.paperWidthDots,
    required this.regularFamily,
    required this.boldFamily,
    required this.mediumFamily,
    required this.fontScale,
    required this.baseWeight,
  }) : _scale = paperWidthDots / 576.0;

  String _currencyLabel = 'ج.م';

  final ui.Canvas canvas;
  final int paperWidthDots;
  final String regularFamily;
  final String boldFamily;
  final String mediumFamily;
  final double fontScale;
  final PrintFontWeight baseWeight;

  final double _scale;

  double _y = 0;

  static const Color _black = Color(0xFF000000);
  static const Color _grey = Color(0xFF444444);
  static const Color _dividerColor = Color(0xFFAAAAAA);

  double _font(double base) => base * fontScale;

  ({String family, FontWeight weight}) _fontFor({bool emphasized = false}) {
    if (emphasized) return (family: boldFamily, weight: FontWeight.w700);
    switch (baseWeight) {
      case PrintFontWeight.normal:
        return (family: regularFamily, weight: FontWeight.w400);
      case PrintFontWeight.medium:
        return (family: mediumFamily, weight: FontWeight.w600);
      case PrintFontWeight.bold:
        return (family: boldFamily, weight: FontWeight.w700);
    }
  }

  double get _paddingTop => 12 * _scale;
  double get _paddingBottom => 16 * _scale;
  double get _paddingH => 14 * _scale;
  double get _sectionGap => 8 * _scale;
  double get _contentWidth => paperWidthDots - 2 * _paddingH;
  double get totalHeight => _y + _paddingBottom;

  Future<void> paint(Receipt r, Uint8List? logoBytes) async {
    _currencyLabel = r.showCurrencySymbol ? 'ج.م' : '';
    canvas.drawRect(
      Rect.fromLTWH(0, 0, paperWidthDots.toDouble(), 100000),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    _y = _paddingTop;

    if (logoBytes != null && logoBytes.isNotEmpty) {
      final ui.Image? logo = await _decodeImage(logoBytes);
      if (logo != null) {
        _drawLogo(logo);
        logo.dispose();
        _gap(_sectionGap * 0.5);
      }
    }

    _header(r);
    _gap(_sectionGap);
    _meta(r);
    _gap(_sectionGap);
    _doubleDivider();
    _gap(_sectionGap);
    _itemsTable(r);
    _gap(_sectionGap);
    _totalsBox(r);
    _gap(_sectionGap * 1.5);
    _divider();
    _gap(_sectionGap);
    _footer(r);
  }

  // ==========================================================================
  // Totals + Payment — ONE unified box
  // ==========================================================================

  void _totalsBox(Receipt r) {
    final List<_TotalsRow> rows = <_TotalsRow>[];

    // ---- Row 1: Invoice total ----
    rows.add(_TotalsRow.text('إجمالي الفاتورة', _money(r.total)));

    // ---- Row 2: Previous balance (if any) ----
    if (r.hasCustomer && (r.previousBalance ?? 0) != 0) {
      rows.add(_TotalsRow.text(
        'الرصيد السابق',
        _money(r.previousBalance!.abs()),
      ));
    }

    // ---- Divider + Grand total ----
    rows.add(_TotalsRow.divider());
    final double totalOwed = r.total + (r.previousBalance ?? 0);
    final bool hasPrev = r.hasCustomer && (r.previousBalance ?? 0) != 0;
    rows.add(_TotalsRow.text(
      hasPrev ? 'المطلوب' : 'إجمالي الفاتورة',
      _money(totalOwed),
      emphasized: true,
    ));

    // ---- Payment block ----
    rows.add(_TotalsRow.divider());
    if (r.hasPayments) {
      if (r.payments.length == 1) {
        // Single payment: show method only
        rows.add(_TotalsRow.text(
          'طريقة الدفع',
          _methodLabel(r.payments.first.method),
        ));
      } else {
        // Multiple payments: show each method + amount
        for (final ReceiptPayment p in r.payments) {
          rows.add(_TotalsRow.text(
            _methodLabel(p.method),
            _money(p.amount),
          ));
        }
      }
    } else {
      rows.add(_TotalsRow.text('طريقة الدفع', 'آجل'));
    }
    rows.add(_TotalsRow.divider());
    rows.add(_TotalsRow.text(
      'المدفوع',
      _money(r.paidAmount),
      emphasized: true,
    ));

    // ---- New balance (if changed) ----
    if (r.hasBalanceChange) {
      rows.add(_TotalsRow.divider());
      final double newBalance = r.newBalance ?? 0;
      if (newBalance > 0) {
        rows.add(_TotalsRow.text(
          'الرصيد الجديد على العميل',
          _money(newBalance),
          emphasized: true,
        ));
      } else if (newBalance < 0) {
        rows.add(_TotalsRow.text(
          'الرصيد الجديد (له عندنا)',
          _money(newBalance.abs()),
          emphasized: true,
        ));
      } else {
        rows.add(_TotalsRow.text(
          'الرصيد الجديد',
          _money(0),
          emphasized: true,
        ));
      }
    }

    _drawTotalsBox(rows);
  }

  void _drawTotalsBox(List<_TotalsRow> rows) {
    final double boxPadH = 12 * _scale;
    final double boxPadV = 10 * _scale;
    final double rowGap = 5 * _scale;
    final double dividerGap = 6 * _scale;
    final double innerWidth = _contentWidth - 2 * boxPadH;

    // ---- Pre-measure all rows ----
    final List<TextPainter?> labelPainters = <TextPainter?>[];
    final List<TextPainter?> valuePainters = <TextPainter?>[];
    double contentH = 0;
    int textRows = 0;

    for (final _TotalsRow row in rows) {
      if (row.isDivider) {
        labelPainters.add(null);
        valuePainters.add(null);
        contentH += dividerGap;
      } else {
        final double fontSize = _font(row.emphasized ? 18 : 16);
        final TextPainter lp = _measure(
          row.label,
          fontSize: fontSize,
          emphasized: true,
        );
        final TextPainter vp = _measure(
          row.value,
          fontSize: fontSize,
          emphasized: row.emphasized,
        );
        labelPainters.add(lp);
        valuePainters.add(vp);
        final double rowH = lp.height > vp.height ? lp.height : vp.height;
        contentH += rowH + (textRows > 0 ? rowGap : 0);
        textRows++;
      }
    }

    final double totalBoxH = contentH + 2 * boxPadV;

    // ---- Draw outer border ----
    canvas.drawRect(
      Rect.fromLTWH(_paddingH, _y, _contentWidth, totalBoxH),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * _scale
        ..color = _black,
    );

    // ---- Draw rows ----
    double currentY = _y + boxPadV;
    bool isFirstText = true;

    for (int i = 0; i < rows.length; i++) {
      final _TotalsRow row = rows[i];

      if (row.isDivider) {
        final double dy = currentY + dividerGap / 2;
        canvas.drawRect(
          Rect.fromLTWH(
            _paddingH + 4 * _scale,
            dy,
            _contentWidth - 8 * _scale,
            0.6 * _scale,
          ),
          Paint()..color = _dividerColor,
        );
        currentY += dividerGap;
        isFirstText = true;
        continue;
      }

      final TextPainter lp = labelPainters[i]!;
      final TextPainter vp = valuePainters[i]!;
      final double rowH = lp.height > vp.height ? lp.height : vp.height;

      if (!isFirstText) currentY += rowGap;

      // Label (right, RTL)
      lp.paint(
        canvas,
        Offset(_paddingH + _contentWidth - boxPadH - lp.width, currentY),
      );
      // Value (left)
      vp.paint(canvas, Offset(_paddingH + boxPadH, currentY));

      currentY += rowH;
      isFirstText = false;
    }

    _y += totalBoxH + 4 * _scale;
  }

  // ==========================================================================
  // Header / Meta / Items
  // ==========================================================================

  Future<ui.Image?> _decodeImage(Uint8List bytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo info = await codec.getNextFrame();
      return info.image;
    } on Object {
      return null;
    }
  }

  void _drawLogo(ui.Image logo) {
    final double targetW = _contentWidth * 0.70;
    final double ratio = logo.height / logo.width;
    final double naturalH = targetW * ratio;
    final double maxH = 180 * _scale;
    final double targetH = naturalH > maxH ? maxH : naturalH;
    final double finalW = targetH / ratio;
    final double x = _paddingH + (_contentWidth - finalW) / 2;

    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(x, _y, finalW, targetH),
      Paint()..filterQuality = FilterQuality.high,
    );

    _y += targetH;
  }

  void _header(Receipt r) {
    _text(r.companyName,
        fontSize: _font(28), emphasized: true, align: TextAlign.center);

    if (r.hasCompanyAddress) {
      _gap(2 * _scale);
      _text(r.companyAddress!,
          fontSize: _font(15), color: _grey, align: TextAlign.center);
    }
    if (r.hasCompanyPhone) {
      _gap(2 * _scale);
      _text(r.companyPhone!,
          fontSize: _font(15), color: _grey, align: TextAlign.center);
    }

    _gap(2 * _scale);
    _text(r.branchName,
        fontSize: _font(18), color: _grey, align: TextAlign.center);

    if (r.hasTaxNumberToPrint) {
      _gap(2 * _scale);
      _text('الرقم الضريبي: ${r.companyTaxNumber}',
          fontSize: _font(14), color: _grey, align: TextAlign.center);
    }
    if (r.hasCommercialRegisterToPrint) {
      _gap(2 * _scale);
      _text('السجل التجاري: ${r.companyCommercialRegister}',
          fontSize: _font(14), color: _grey, align: TextAlign.center);
    }

    _gap(_sectionGap);
    _chip('فاتورة مبيعات', fontSize: _font(20));
  }

  void _meta(Receipt r) {
    _metaRow('رقم الفاتورة', r.invoiceNumber ?? '—', bold: true);
    _metaRow('التاريخ', _formatDayAndDate(r.dateTime));
    if (r.cashierName != null && r.cashierName!.trim().isNotEmpty) {
      _metaRow('الكاشير', r.cashierName!);
    }
    if (r.hasCustomer) {
      _metaRow('العميل', r.customerName!);
      if (r.hasCustomerAddress) _metaRow('عنوان العميل', r.customerAddress!);
      if (r.hasCustomerPhone) _metaRow('هاتف العميل', r.customerPhone!);
    }
  }

  void _itemsTable(Receipt r) {
    final double w = _contentWidth;
    final double colNumW = 26 * _scale;
    final double colQtyW = w * 0.20;
    final double colPriceW = w * 0.20;
    final double colTotalW = w * 0.24;
    final double colNameW = w - colNumW - colQtyW - colPriceW - colTotalW;

    double totalQuantity = 0;
    for (final line in r.lines) {
      totalQuantity += line.quantity;
    }

    _row(
      cells: <_Cell>[
        _Cell('م', width: colNumW, bold: true, align: TextAlign.center),
        _Cell('الصنف', width: colNameW, bold: true, align: TextAlign.right),
        _Cell('الكمية', width: colQtyW, bold: true, align: TextAlign.center),
        _Cell('السعر', width: colPriceW, bold: true, align: TextAlign.center),
        _Cell('الإجمالي',
            width: colTotalW, bold: true, align: TextAlign.center),
      ],
      fontSize: _font(15),
      topPad: 8 * _scale,
      bottomPad: 8 * _scale,
    );

    for (int i = 0; i < r.lines.length; i++) {
      final ReceiptLine line = r.lines[i];
      _row(
        cells: <_Cell>[
          _Cell('${i + 1}', width: colNumW, align: TextAlign.center),
          _Cell(line.productName, width: colNameW, align: TextAlign.right),
          _Cell('${_qty(line.quantity)} ${line.unitName}',
              width: colQtyW, align: TextAlign.center),
          _Cell(_money(line.unitPrice),
              width: colPriceW, align: TextAlign.center),
          _Cell(_money(line.lineTotal),
              width: colTotalW, bold: true, align: TextAlign.center),
        ],
        fontSize: _font(15),
        topPad: 8 * _scale,
        bottomPad: 8 * _scale,
      );
    }

    _row(
      cells: <_Cell>[
        _Cell('', width: colNumW, align: TextAlign.center),
        _Cell('المجموع الفرعي',
            width: colNameW, bold: true, align: TextAlign.right),
        _Cell(_qty(totalQuantity), width: colQtyW, align: TextAlign.center),
        _Cell('', width: colPriceW, align: TextAlign.center),
        _Cell(_money(r.subtotal),
            width: colTotalW, bold: true, align: TextAlign.center),
      ],
      fontSize: _font(15),
      topPad: 8 * _scale,
      bottomPad: 8 * _scale,
    );

    if (r.hasDiscountToPrint) {
      _row(
        cells: <_Cell>[
          _Cell('', width: colNumW, align: TextAlign.center),
          _Cell('الخصم', width: colNameW, bold: true, align: TextAlign.right),
          _Cell('', width: colQtyW, align: TextAlign.center),
          _Cell('', width: colPriceW, align: TextAlign.center),
          _Cell('- ${_money(r.discount)}',
              width: colTotalW, bold: true, align: TextAlign.center),
        ],
        fontSize: _font(15),
        topPad: 8 * _scale,
        bottomPad: 8 * _scale,
      );
    }

    if (r.hasTaxToPrint) {
      _row(
        cells: <_Cell>[
          _Cell('', width: colNumW, align: TextAlign.center),
          _Cell('الضريبة',
              width: colNameW, bold: true, align: TextAlign.right),
          _Cell('', width: colQtyW, align: TextAlign.center),
          _Cell('', width: colPriceW, align: TextAlign.center),
          _Cell(_money(r.taxAmount),
              width: colTotalW, bold: true, align: TextAlign.center),
        ],
        fontSize: _font(15),
        topPad: 8 * _scale,
        bottomPad: 8 * _scale,
      );
    }
  }

  // ==========================================================================
  // Footer + helpers
  // ==========================================================================

  void _footer(Receipt r) {
    _text(_footerText(r),
        fontSize: _font(15), color: _grey, align: TextAlign.center);
  }

  void _metaRow(String label, String value, {bool bold = false}) {
    final double fontSize = _font(16);

    final TextPainter labelPainter = _measure('$label:',
        fontSize: fontSize,
        bold: true,
        align: TextAlign.right,
        maxWidth: double.infinity);
    final double gap = 8 * _scale;
    final double naturalLabelW = labelPainter.width + gap;
    final double maxLabelW = _contentWidth * 0.6;
    final double labelW = naturalLabelW < maxLabelW ? naturalLabelW : maxLabelW;
    final double valueMaxW = _contentWidth - labelW;

    final TextPainter valuePainter = _measure(value,
        fontSize: fontSize,
        bold: bold,
        align: TextAlign.left,
        maxWidth: valueMaxW);
    final double rowH = labelPainter.height > valuePainter.height
        ? labelPainter.height
        : valuePainter.height;

    labelPainter.paint(canvas,
        Offset(_paddingH + _contentWidth - labelPainter.width, _y));
    valuePainter.paint(canvas, Offset(_paddingH, _y));

    _y += rowH + 3 * _scale;
  }

  void _text(String text,
      {required double fontSize,
      bool bold = false,
      bool emphasized = false,
      Color color = _black,
      TextAlign align = TextAlign.right}) {
    if (align == TextAlign.center) {
      final TextPainter natural = _measure(text,
          fontSize: fontSize,
          bold: bold,
          emphasized: emphasized,
          color: color,
          align: TextAlign.left,
          maxWidth: double.infinity);
      if (natural.width <= _contentWidth) {
        natural.paint(canvas,
            Offset(_paddingH + (_contentWidth - natural.width) / 2, _y));
        _y += natural.height;
        return;
      }
    }
    final TextPainter painter = _measure(text,
        fontSize: fontSize,
        bold: bold,
        emphasized: emphasized,
        color: color,
        align: align);
    painter.paint(canvas, Offset(_paddingH, _y));
    _y += painter.height;
  }

  void _chip(String text, {required double fontSize}) {
    final TextPainter painter = _measure(text,
        fontSize: fontSize, emphasized: true, align: TextAlign.center);

    final double padH = 24 * _scale;
    final double padV = 8 * _scale;
    final double chipW = painter.width + padH * 2;
    final double chipH = painter.height + padV * 2;
    final double chipX = (_contentWidth - chipW) / 2 + _paddingH;

    final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(chipX, _y, chipW, chipH), Radius.circular(4 * _scale));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * _scale
          ..color = _black);
    painter.paint(canvas, Offset(chipX + padH, _y + padV));

    _y += chipH;
  }

  void _row(
      {required List<_Cell> cells,
      required double fontSize,
      required double topPad,
      required double bottomPad}) {
    final double cellInsetH = 4 * _scale;
    final List<TextPainter> painters = <TextPainter>[];
    double maxH = 0;

    for (final _Cell cell in cells) {
      final TextPainter painter = _measure(cell.text,
          fontSize: fontSize,
          bold: cell.bold,
          align: cell.align,
          maxWidth: cell.width - cellInsetH * 2);
      painters.add(painter);
      if (painter.height > maxH) maxH = painter.height;
    }

    final double rowH = maxH + topPad + bottomPad;
    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * _scale
      ..color = _black;

    double x = _paddingH + _contentWidth;
    for (int i = 0; i < cells.length; i++) {
      final _Cell cell = cells[i];
      x -= cell.width;
      final TextPainter painter = painters[i];
      final double contentY = _y + topPad + (maxH - painter.height) / 2;
      painter.paint(canvas, Offset(x + cellInsetH, contentY));
      canvas.drawRect(Rect.fromLTWH(x, _y, cell.width, rowH), gridPaint);
    }

    canvas.drawRect(
        Rect.fromLTWH(
            _paddingH, _y + rowH - 0.5 * _scale, _contentWidth, 0.5 * _scale),
        Paint()..color = const Color(0xFF888888));
    _y += rowH;
  }

  void _divider() {
    canvas.drawRect(
        Rect.fromLTWH(_paddingH, _y, _contentWidth, 0.7 * _scale),
        Paint()..color = const Color(0xFF666666));
    _y += 1 * _scale;
  }

  void _doubleDivider() {
    _divider();
    _gap(2 * _scale);
    _divider();
  }

  void _gap(double pixels) {
    _y += pixels;
  }

  TextPainter _measure(String text,
      {required double fontSize,
      bool bold = false,
      bool emphasized = false,
      Color color = _black,
      TextAlign align = TextAlign.right,
      double? maxWidth}) {
    final bool useBold = bold || emphasized;
    final ({String family, FontWeight weight}) style =
        _fontFor(emphasized: useBold);

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize * _scale,
          color: color,
          fontFamily: style.family,
          fontWeight: style.weight,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: align,
    );
    painter.layout(maxWidth: maxWidth ?? _contentWidth);
    return painter;
  }

  String _money(double value) =>
      ReceiptNumberFormat.money(value, currency: _currencyLabel);
  static String _qty(double value) => ReceiptNumberFormat.quantity(value);

  static const List<String> _days = <String>[
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد'
  ];

  static String _formatDayAndDate(DateTime value) {
    final DateTime l = value.toLocal();
    final String day = _days[(l.weekday - 1).clamp(0, 6)];
    final String y = l.year.toString().padLeft(4, '0');
    final String m = l.month.toString().padLeft(2, '0');
    final String d = l.day.toString().padLeft(2, '0');
    final int h24 = l.hour;
    final int h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final String ampm = h24 >= 12 ? 'م' : 'ص';
    final String hh = h12.toString().padLeft(2, '0');
    final String mm = l.minute.toString().padLeft(2, '0');
    return '$day، $y/$m/$d — $hh:$mm $ampm';
  }

  static String _methodLabel(String method) => switch (method) {
        'cash' => 'نقدي',
        'card' => 'بطاقة',
        'instapay' => 'InstaPay',
        'bank_transfer' => 'تحويل بنكي',
        _ => 'أخرى',
      };

  static String _footerText(Receipt r) {
    final String? custom = r.footer;
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return 'شكرًا لتعاملكم معنا';
  }
}

class _Cell {
  const _Cell(this.text,
      {required this.width, this.bold = false, this.align = TextAlign.right});
  final String text;
  final double width;
  final bool bold;
  final TextAlign align;
}

// ============================================================================
// Totals row model
// ============================================================================

class _TotalsRow {
  const _TotalsRow.text(this.label, this.value, {this.emphasized = false})
      : isDivider = false;
  const _TotalsRow.divider()
      : label = '',
        value = '',
        emphasized = false,
        isDivider = true;

  final String label;
  final String value;
  final bool emphasized;
  final bool isDivider;
}
