// lib/features/pos/data/services/esc_pos_receipt_builder.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:google_fonts/google_fonts.dart';

import '../../../settings/domain/entities/company_settings.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/receipt_number_format.dart';
import '../../../settings/domain/entities/print_style_settings.dart';

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

    return <int>[
      ..._init,
      ...raster,
      ..._feedAndCut,
    ];
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
    final TextStyle medium =
        GoogleFonts.cairo(fontWeight: FontWeight.w600);
    final TextStyle bold =
        GoogleFonts.cairo(fontWeight: FontWeight.w700);

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
        if (x + 1 < width) {
          gray[i + 1] += err * 7 / 16;
        }
        if (y + 1 < height) {
          if (x > 0) gray[i + width - 1] += err * 3 / 16;
          gray[i + width] += err * 5 / 16;
          if (x + 1 < width) {
            gray[i + width + 1] += err * 1 / 16;
          }
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
          if (gray[rowStart + x] < 128) {
            byte |= 0x80 >> bit;
          }
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

  double _font(double base) => base * fontScale;

  ({String family, FontWeight weight}) _fontFor({bool emphasized = false}) {
    if (emphasized) {
      return (family: boldFamily, weight: FontWeight.w700);
    }
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
    
    // ⬇️ قسم الإجماليات الجديد (بالترتيب المطلوب)
    _totalsSection(r);

    _gap(_sectionGap * 1.5);
    _divider();
    _gap(_sectionGap);
    _footer(r);
  }

  // ⬇️ دالة جديدة لقسم الإجماليات
  void _totalsSection(Receipt r) {
    // 1. الإجمالي الحالي (قيمة الفاتورة)
    _kvRow('الإجمالي الحالي', _money(r.total));

    // 2. الرصيد السابق (إذا وجد عميل ورصيد)
    if (r.hasCustomer && (r.previousBalance ?? 0) != 0) {
      _gap(4 * _scale);
      _kvRow('الرصيد السابق', _money(r.previousBalance!.abs()));
    }

    // 3. الإجمالي الكلي (الفاتورة + الرصيد السابق)
    final double totalOwed = r.total + (r.previousBalance ?? 0);
    _gap(4 * _scale);
    _grandTotal(r, totalOwed);

    // 4. المدفوع + طريقة الدفع
    _gap(4 * _scale);
    _kvRow('طريقة الدفع', _paymentMethodLabel(r));
    _gap(4 * _scale);
    _kvRow('المدفوع', _money(r.paidAmount));

    // 5. الرصيد الجديد (إذا وجد)
    if (r.hasBalanceChange) {
      _gap(4 * _scale);
      _divider();
      _gap(4 * _scale);
      _newBalanceBlock(r);
    }
  }

  Future<ui.Image?> _decodeImage(Uint8List bytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo info = await codec.getNextFrame();
      return info.image;
    } on Object {
      return null;
    }
  }

  // ⬇️ تم تكبير اللوجو هنا (من 0.55 إلى 0.70، ومن 140 إلى 180)
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
    _text(r.companyName, fontSize: _font(28), emphasized: true, align: TextAlign.center);

    if (r.hasCompanyAddress) {
      _gap(2 * _scale);
      _text(r.companyAddress!, fontSize: _font(15), color: _grey, align: TextAlign.center);
    }
    if (r.hasCompanyPhone) {
      _gap(2 * _scale);
      _text(r.companyPhone!, fontSize: _font(15), color: _grey, align: TextAlign.center);
    }

    _gap(2 * _scale);
    _text(r.branchName, fontSize: _font(18), color: _grey, align: TextAlign.center);

    if (r.hasTaxNumberToPrint) {
      _gap(2 * _scale);
      _text('الرقم الضريبي: ${r.companyTaxNumber}', fontSize: _font(14), color: _grey, align: TextAlign.center);
    }
    if (r.hasCommercialRegisterToPrint) {
      _gap(2 * _scale);
      _text('السجل التجاري: ${r.companyCommercialRegister}', fontSize: _font(14), color: _grey, align: TextAlign.center);
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
        _Cell('الإجمالي', width: colTotalW, bold: true, align: TextAlign.center),
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
          _Cell('${_qty(line.quantity)} ${line.unitName}', width: colQtyW, align: TextAlign.center),
          _Cell(_money(line.unitPrice), width: colPriceW, align: TextAlign.center),
          _Cell(_money(line.lineTotal), width: colTotalW, bold: true, align: TextAlign.center),
        ],
        fontSize: _font(15),
        topPad: 8 * _scale,
        bottomPad: 8 * _scale,
      );
    }

    _row(
      cells: <_Cell>[
        _Cell('', width: colNumW, align: TextAlign.center),
        _Cell('المجموع الفرعي', width: colNameW, bold: true, align: TextAlign.right),
        _Cell(_qty(totalQuantity), width: colQtyW, align: TextAlign.center),
        _Cell('', width: colPriceW, align: TextAlign.center),
        _Cell(_money(r.subtotal), width: colTotalW, bold: true, align: TextAlign.center),
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
          _Cell('- ${_money(r.discount)}', width: colTotalW, bold: true, align: TextAlign.center),
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
          _Cell('الضريبة', width: colNameW, bold: true, align: TextAlign.right),
          _Cell('', width: colQtyW, align: TextAlign.center),
          _Cell('', width: colPriceW, align: TextAlign.center),
          _Cell(_money(r.taxAmount), width: colTotalW, bold: true, align: TextAlign.center),
        ],
        fontSize: _font(15),
        topPad: 8 * _scale,
        bottomPad: 8 * _scale,
      );
    }
  }

  void _grandTotal(Receipt r, double totalOwed) {
    final double fontSize = _font(22);
    final double boxPad = 10 * _scale;

    final String labelText = ((r.previousBalance ?? 0) != 0) ? 'الإجمالي الكلي' : 'إجمالي الفاتورة';

    final TextPainter label = _measure(labelText, fontSize: fontSize, emphasized: true);
    final TextPainter value = _measure(_money(totalOwed), fontSize: fontSize, emphasized: true);
    final double lineH = label.height > value.height ? label.height : value.height;
    final double boxH = lineH + boxPad * 2;

    canvas.drawRect(
      Rect.fromLTWH(_paddingH, _y, _contentWidth, boxH),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5 * _scale..color = _black,
    );

    label.paint(canvas, Offset(_paddingH + _contentWidth - boxPad - label.width, _y + boxPad));
    value.paint(canvas, Offset(_paddingH + boxPad, _y + boxPad));

    _y += boxH;
  }

  void _newBalanceBlock(Receipt r) {
    final double newBalance = r.newBalance ?? 0;
    final String label;
    final String value;
    if (newBalance > 0) {
      label = 'الرصيد الجديد على العميل';
      value = _money(newBalance);
    } else if (newBalance < 0) {
      label = 'الرصيد الجديد (له عندنا)';
      value = _money(newBalance.abs());
    } else {
      label = 'الرصيد الجديد';
      value = _money(0);
    }

    _balanceBox(label, value);
  }

  void _balanceBox(String label, String value) {
    final double fontSize = _font(18);
    final double boxPad = 8 * _scale;

    final TextPainter labelP = _measure(label, fontSize: fontSize, emphasized: true);
    final TextPainter valueP = _measure(value, fontSize: fontSize, emphasized: true);
    final double lineH = labelP.height > valueP.height ? labelP.height : valueP.height;
    final double boxH = lineH + boxPad * 2;

    canvas.drawRect(
      Rect.fromLTWH(_paddingH, _y, _contentWidth, boxH),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2 * _scale..color = _black,
    );

    labelP.paint(canvas, Offset(_paddingH + _contentWidth - boxPad - labelP.width, _y + boxPad));
    valueP.paint(canvas, Offset(_paddingH + boxPad, _y + boxPad));

    _y += boxH;
  }

  void _footer(Receipt r) {
    _text(_footerText(r), fontSize: _font(15), color: _grey, align: TextAlign.center);
  }

  void _metaRow(String label, String value, {bool bold = false}) {
    final double fontSize = _font(16);

    final TextPainter labelPainter = _measure('$label:', fontSize: fontSize, bold: true, align: TextAlign.right, maxWidth: double.infinity);
    final double gap = 8 * _scale;
    final double naturalLabelW = labelPainter.width + gap;
    final double maxLabelW = _contentWidth * 0.6;
    final double labelW = naturalLabelW < maxLabelW ? naturalLabelW : maxLabelW;
    final double valueMaxW = _contentWidth - labelW;

    final TextPainter valuePainter = _measure(value, fontSize: fontSize, bold: bold, align: TextAlign.left, maxWidth: valueMaxW);
    final double rowH = labelPainter.height > valuePainter.height ? labelPainter.height : valuePainter.height;

    labelPainter.paint(canvas, Offset(_paddingH + _contentWidth - labelPainter.width, _y));
    valuePainter.paint(canvas, Offset(_paddingH, _y));

    _y += rowH + 3 * _scale;
  }

  void _kvRow(String label, String value, {bool emphasized = false}) {
    final double labelFont = _font(16);
    final double valueFont = emphasized ? _font(20) : _font(16);

    final TextPainter labelPainter = _measure(label, fontSize: labelFont, bold: true);
    final TextPainter valuePainter = _measure(value, fontSize: valueFont, bold: emphasized);
    final double rowH = labelPainter.height > valuePainter.height ? labelPainter.height : valuePainter.height;

    labelPainter.paint(canvas, Offset(_paddingH + _contentWidth - labelPainter.width, _y));
    valuePainter.paint(canvas, Offset(_paddingH, _y));

    _y += rowH + 4 * _scale;
  }

  void _text(String text, {required double fontSize, bool bold = false, bool emphasized = false, Color color = _black, TextAlign align = TextAlign.right}) {
    if (align == TextAlign.center) {
      final TextPainter natural = _measure(text, fontSize: fontSize, bold: bold, emphasized: emphasized, color: color, align: TextAlign.left, maxWidth: double.infinity);
      if (natural.width <= _contentWidth) {
        natural.paint(canvas, Offset(_paddingH + (_contentWidth - natural.width) / 2, _y));
        _y += natural.height;
        return;
      }
    }
    final TextPainter painter = _measure(text, fontSize: fontSize, bold: bold, emphasized: emphasized, color: color, align: align);
    painter.paint(canvas, Offset(_paddingH, _y));
    _y += painter.height;
  }

  void _chip(String text, {required double fontSize}) {
    final TextPainter painter = _measure(text, fontSize: fontSize, emphasized: true, align: TextAlign.center);

    final double padH = 24 * _scale;
    final double padV = 8 * _scale;
    final double chipW = painter.width + padH * 2;
    final double chipH = painter.height + padV * 2;
    final double chipX = (_contentWidth - chipW) / 2 + _paddingH;

    final RRect rrect = RRect.fromRectAndRadius(Rect.fromLTWH(chipX, _y, chipW, chipH), Radius.circular(4 * _scale));
    canvas.drawRRect(rrect, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2 * _scale..color = _black);
    painter.paint(canvas, Offset(chipX + padH, _y + padV));

    _y += chipH;
  }

  void _row({required List<_Cell> cells, required double fontSize, required double topPad, required double bottomPad}) {
    final double cellInsetH = 4 * _scale;
    final List<TextPainter> painters = <TextPainter>[];
    double maxH = 0;

    for (final _Cell cell in cells) {
      final TextPainter painter = _measure(cell.text, fontSize: fontSize, bold: cell.bold, align: cell.align, maxWidth: cell.width - cellInsetH * 2);
      painters.add(painter);
      if (painter.height > maxH) maxH = painter.height;
    }

    final double rowH = maxH + topPad + bottomPad;
    final Paint gridPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8 * _scale..color = _black;

    double x = _paddingH + _contentWidth;
    for (int i = 0; i < cells.length; i++) {
      final _Cell cell = cells[i];
      x -= cell.width;
      final TextPainter painter = painters[i];
      final double contentY = _y + topPad + (maxH - painter.height) / 2;
      painter.paint(canvas, Offset(x + cellInsetH, contentY));
      canvas.drawRect(Rect.fromLTWH(x, _y, cell.width, rowH), gridPaint);
    }

    canvas.drawRect(Rect.fromLTWH(_paddingH, _y + rowH - 0.5 * _scale, _contentWidth, 0.5 * _scale), Paint()..color = const Color(0xFF888888));
    _y += rowH;
  }

  void _divider() {
    canvas.drawRect(Rect.fromLTWH(_paddingH, _y, _contentWidth, 0.7 * _scale), Paint()..color = const Color(0xFF666666));
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

  TextPainter _measure(String text, {required double fontSize, bool bold = false, bool emphasized = false, Color color = _black, TextAlign align = TextAlign.right, double? maxWidth}) {
    final bool useBold = bold || emphasized;
    final ({String family, FontWeight weight}) style = _fontFor(emphasized: useBold);

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

  String _money(double value) => ReceiptNumberFormat.money(value, currency: _currencyLabel);
  static String _qty(double value) => ReceiptNumberFormat.quantity(value);

  static const List<String> _days = <String>['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

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

  // ⬇️ تمت إعادة الدالة
  static String _paymentMethodLabel(Receipt r) {
    if (r.paidAmount <= 0) return 'آجل';
    if (r.paidAmount >= r.total) return 'نقدي';
    return 'نقدي (جزئي)';
  }

  static String _footerText(Receipt r) {
    final String? custom = r.footer;
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return 'شكرًا لتعاملكم معنا';
  }
}

class _Cell {
  const _Cell(this.text, {required this.width, this.bold = false, this.align = TextAlign.right});
  final String text;
  final double width;
  final bool bold;
  final TextAlign align;
}
