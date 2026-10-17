// lib/features/pos/data/services/esc_pos_receipt_builder.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:google_fonts/google_fonts.dart';

import '../../../settings/domain/entities/company_settings.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/receipt_number_format.dart';

/// Builds an ESC/POS byte stream from a [Receipt] by rendering the whole
/// document as a 1-bit bitmap and sending it as a `GS v 0` raster command.
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

    final double clampedScale = fontScale.clamp(0.8, 1.6);

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

  /// Loads Cairo from `assets/fonts/`. Returns `false` when the files are not
  /// bundled, so the caller falls back to google_fonts (needs internet once).
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

    // Prefer Cairo bundled with the app: printing must work without internet.
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

    const int threshold = 160;

    final Uint8List raster = Uint8List(widthBytes * height);
    int offset = 0;
    for (int y = 0; y < height; y++) {
      final int rowStart = y * width * 4;
      for (int bx = 0; bx < widthBytes; bx++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final int x = bx * 8 + bit;
          if (x >= width) break;
          final int idx = rowStart + x * 4;
          final int a = pixels[idx + 3];
          if (a < 128) continue;
          final int r = pixels[idx];
          final int g = pixels[idx + 1];
          final int b = pixels[idx + 2];
          final int lum = (r * 299 + g * 587 + b * 114) ~/ 1000;
          if (lum < threshold) {
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
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        paperWidthDots.toDouble(),
        100000,
      ),
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
    _grandTotal(r);
    _gap(_sectionGap);
    _paymentBlock(r);
    if (r.hasBalanceChange) {
      _gap(_sectionGap);
      _divider();
      _gap(_sectionGap);
      _balanceBlock(r);
    }
    _gap(_sectionGap * 1.5);
    _divider();
    _gap(_sectionGap);
    _footer(r);
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

  void _drawLogo(ui.Image logo) {
    final double targetW = _contentWidth * 0.55;
    final double ratio = logo.height / logo.width;
    final double naturalH = targetW * ratio;

    final double maxH = 140 * _scale;
    final double targetH = naturalH > maxH ? maxH : naturalH;
    final double finalW = targetH / ratio;

    final double x = _paddingH + (_contentWidth - finalW) / 2;

    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(
        0,
        0,
        logo.width.toDouble(),
        logo.height.toDouble(),
      ),
      Rect.fromLTWH(x, _y, finalW, targetH),
      Paint()..filterQuality = FilterQuality.high,
    );

    _y += targetH;
  }

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  void _header(Receipt r) {
    _text(
      r.companyName,
      fontSize: _font(24),
      emphasized: true,
      align: TextAlign.center,
    );

    if (r.hasCompanyAddress) {
      _gap(2 * _scale);
      _text(
        r.companyAddress!,
        fontSize: _font(13),
        color: _grey,
        align: TextAlign.center,
      );
    }

    if (r.hasCompanyPhone) {
      _gap(2 * _scale);
      _text(
        r.companyPhone!,
        fontSize: _font(13),
        color: _grey,
        align: TextAlign.center,
      );
    }

    _gap(2 * _scale);
    _text(
      r.branchName,
      fontSize: _font(15),
      color: _grey,
      align: TextAlign.center,
    );

    if (r.hasTaxNumberToPrint) {
      _gap(2 * _scale);
      _text(
        'الرقم الضريبي: ${r.companyTaxNumber}',
        fontSize: _font(12),
        color: _grey,
        align: TextAlign.center,
      );
    }

    if (r.hasCommercialRegisterToPrint) {
      _gap(2 * _scale);
      _text(
        'السجل التجاري: ${r.companyCommercialRegister}',
        fontSize: _font(12),
        color: _grey,
        align: TextAlign.center,
      );
    }

    _gap(_sectionGap);
    _chip('فاتورة مبيعات', fontSize: _font(17));
  }

  void _meta(Receipt r) {
    _metaRow('رقم الفاتورة', r.invoiceNumber ?? '—', bold: true);
    _metaRow('التاريخ', _formatDayAndDate(r.dateTime));

    if (r.hasCustomer) {
      _metaRow('العميل', r.customerName!);

      if (r.hasCustomerAddress) {
        _metaRow('عنوان العميل', r.customerAddress!);
      }

      if (r.hasCustomerPhone) {
        _metaRow('هاتف العميل', r.customerPhone!);
      }
    }

    if (r.cashierName != null && r.cashierName!.trim().isNotEmpty) {
      _metaRow('الكاشير', r.cashierName!);
    }
  }

  void _itemsTable(Receipt r) {
    final double w = _contentWidth;
    final double colNumW = 24 * _scale;
    final double colQtyW = w * 0.20;
    final double colPriceW = w * 0.20;
    final double colTotalW = w * 0.24;
    final double colNameW = w - colNumW - colQtyW - colPriceW - colTotalW;

    _row(
      cells: <_Cell>[
        _Cell('م',
            width: colNumW, bold: true, align: TextAlign.center),
        _Cell('الصنف',
            width: colNameW, bold: true, align: TextAlign.right),
        _Cell('الكمية',
            width: colQtyW, bold: true, align: TextAlign.center),
        _Cell('السعر',
            width: colPriceW, bold: true, align: TextAlign.center),
        _Cell('الإجمالي',
            width: colTotalW, bold: true, align: TextAlign.center),
      ],
      fontSize: _font(13),
      topPad: 6 * _scale,
      bottomPad: 6 * _scale,
      backgroundColor: const Color(0xFFDDDDDD),
    );

    for (int i = 0; i < r.lines.length; i++) {
      final ReceiptLine line = r.lines[i];
      final Color? bg = i.isOdd ? const Color(0xFFF2F2F2) : null;
      _row(
        cells: <_Cell>[
          _Cell('${i + 1}',
              width: colNumW, align: TextAlign.center),
          _Cell(line.productName,
              width: colNameW, align: TextAlign.right),
          _Cell('${_qty(line.quantity)} ${line.unitName}',
              width: colQtyW, align: TextAlign.center),
          _Cell(_money(line.unitPrice),
              width: colPriceW, align: TextAlign.center),
          _Cell(_money(line.lineTotal),
              width: colTotalW, bold: true, align: TextAlign.center),
        ],
        fontSize: _font(13),
        topPad: 5 * _scale,
        bottomPad: 5 * _scale,
        backgroundColor: bg,
      );
    }

    _row(
      cells: <_Cell>[
        _Cell('', width: colNumW, align: TextAlign.center),
        _Cell('المجموع الفرعي',
            width: colNameW, bold: true, align: TextAlign.right),
        _Cell('${r.lines.length}',
            width: colQtyW, align: TextAlign.center),
        _Cell('', width: colPriceW, align: TextAlign.center),
        _Cell(_money(r.subtotal),
            width: colTotalW, bold: true, align: TextAlign.center),
      ],
      fontSize: _font(13),
      topPad: 6 * _scale,
      bottomPad: 6 * _scale,
      backgroundColor: const Color(0xFFE8E8E8),
    );

    if (r.hasDiscountToPrint) {
      _row(
        cells: <_Cell>[
          _Cell('', width: colNumW, align: TextAlign.center),
          _Cell('الخصم',
              width: colNameW, bold: true, align: TextAlign.right),
          _Cell('', width: colQtyW, align: TextAlign.center),
          _Cell('', width: colPriceW, align: TextAlign.center),
          _Cell('- ${_money(r.discount)}',
              width: colTotalW, bold: true, align: TextAlign.center),
        ],
        fontSize: _font(13),
        topPad: 5 * _scale,
        bottomPad: 5 * _scale,
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
        fontSize: _font(13),
        topPad: 5 * _scale,
        bottomPad: 5 * _scale,
      );
    }
  }

  void _grandTotal(Receipt r) {
    final double fontSize = _font(20);
    final double boxPad = 8 * _scale;

    final TextPainter label = _measure(
      'إجمالي الفاتورة',
      fontSize: fontSize,
      emphasized: true,
    );
    final TextPainter value = _measure(
      _money(r.total),
      fontSize: fontSize,
      emphasized: true,
    );
    final double lineH =
        label.height > value.height ? label.height : value.height;
    final double boxH = lineH + boxPad * 2;

    canvas.drawRect(
      Rect.fromLTWH(_paddingH, _y, _contentWidth, boxH),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * _scale
        ..color = _black,
    );

    label.paint(
      canvas,
      Offset(_paddingH + _contentWidth - boxPad - label.width, _y + boxPad),
    );
    value.paint(canvas, Offset(_paddingH + boxPad, _y + boxPad));

    _y += boxH;
  }

  /// Payment block — method and paid amount only.
  ///
  /// The resulting balance is reported in [_balanceBlock] separately; no
  /// change / excess / "الباقي للعميل" is computed here because the
  /// simplified model treats `paidAmount` as one lump sum that is applied
  /// to (invoice + old balance) as a whole.
  void _paymentBlock(Receipt r) {
    _kvRow('طريقة الدفع', _paymentMethodLabel(r));
    _kvRow('المدفوع', _money(r.paidAmount));
  }

  /// Balance block — reports the previous balance and the resulting one.
  ///
  /// * `newBalance > 0` → customer owes us (مدين).
  /// * `newBalance < 0` → we owe the customer (له عندنا).
  /// * `newBalance = 0` → settled.
  void _balanceBlock(Receipt r) {
    _kvRow('الرصيد السابق', _money(r.previousBalance ?? 0));

    final double newBalance = r.newBalance ?? 0;
    if (newBalance > 0) {
      _kvRow(
        'الرصيد الجديد على العميل',
        _money(newBalance),
        emphasized: true,
      );
    } else if (newBalance < 0) {
      _kvRow(
        'الرصيد الجديد (له عندنا)',
        _money(newBalance.abs()),
        emphasized: true,
      );
    } else {
      _kvRow(
        'الرصيد الجديد',
        _money(0),
        emphasized: true,
      );
    }
  }

  void _footer(Receipt r) {
    _text(
      _footerText(r),
      fontSize: _font(14),
      color: _grey,
      align: TextAlign.center,
    );
  }

  void _metaRow(String label, String value, {bool bold = false}) {
    final double labelW = 92 * _scale;
    final double fontSize = _font(14);

    final TextPainter labelPainter = _measure(
      '$label:',
      fontSize: fontSize,
      bold: true,
    );
    final TextPainter valuePainter = _measure(
      value,
      fontSize: fontSize,
      bold: bold,
    );
    final double rowH = labelPainter.height > valuePainter.height
        ? labelPainter.height
        : valuePainter.height;

    labelPainter.paint(
      canvas,
      Offset(_paddingH + _contentWidth - labelW, _y),
    );
    valuePainter.paint(canvas, Offset(_paddingH, _y));

    _y += rowH + 2 * _scale;
  }

  void _kvRow(String label, String value, {bool emphasized = false}) {
    final double labelFont = _font(14);
    final double valueFont = emphasized ? _font(17) : _font(14);

    final TextPainter labelPainter = _measure(
      label,
      fontSize: labelFont,
      bold: true,
    );
    final TextPainter valuePainter = _measure(
      value,
      fontSize: valueFont,
      bold: emphasized,
    );
    final double rowH = labelPainter.height > valuePainter.height
        ? labelPainter.height
        : valuePainter.height;

    labelPainter.paint(
      canvas,
      Offset(_paddingH + _contentWidth - labelPainter.width, _y),
    );
    valuePainter.paint(canvas, Offset(_paddingH, _y));

    _y += rowH + 3 * _scale;
  }

  void _text(
    String text, {
    required double fontSize,
    bool bold = false,
    bool emphasized = false,
    Color color = _black,
    TextAlign align = TextAlign.right,
  }) {
    final TextPainter painter = _measure(
      text,
      fontSize: fontSize,
      bold: bold,
      emphasized: emphasized,
      color: color,
      align: align,
    );
    painter.paint(canvas, Offset(_paddingH, _y));
    _y += painter.height;
  }

  void _chip(String text, {required double fontSize}) {
    final TextPainter painter = _measure(
      text,
      fontSize: fontSize,
      emphasized: true,
      align: TextAlign.center,
    );

    final double padH = 22 * _scale;
    final double padV = 6 * _scale;
    final double chipW = painter.width + padH * 2;
    final double chipH = painter.height + padV * 2;
    final double chipX = (_contentWidth - chipW) / 2 + _paddingH;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(chipX, _y, chipW, chipH),
      Radius.circular(3 * _scale),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * _scale
        ..color = _black,
    );
    painter.paint(canvas, Offset(chipX + padH, _y + padV));

    _y += chipH;
  }

  void _row({
    required List<_Cell> cells,
    required double fontSize,
    required double topPad,
    required double bottomPad,
    Color? backgroundColor,
  }) {
    final List<TextPainter> painters = <TextPainter>[];
    double maxH = 0;
    for (final _Cell cell in cells) {
      final TextPainter painter = _measure(
        cell.text,
        fontSize: fontSize,
        bold: cell.bold,
        align: cell.align,
        maxWidth: cell.width - 4 * _scale,
      );
      painters.add(painter);
      if (painter.height > maxH) maxH = painter.height;
    }

    final double rowH = maxH + topPad + bottomPad;

    if (backgroundColor != null) {
      canvas.drawRect(
        Rect.fromLTWH(_paddingH, _y, _contentWidth, rowH),
        Paint()..color = backgroundColor,
      );
    }

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
      painter.paint(canvas, Offset(x + 2 * _scale, contentY));
      // Cell border: draws the vertical grid lines of the table.
      canvas.drawRect(Rect.fromLTWH(x, _y, cell.width, rowH), gridPaint);
    }

    canvas.drawRect(
      Rect.fromLTWH(
        _paddingH,
        _y + rowH - 0.5 * _scale,
        _contentWidth,
        0.5 * _scale,
      ),
      Paint()..color = const Color(0xFF888888),
    );

    _y += rowH;
  }

  void _divider() {
    canvas.drawRect(
      Rect.fromLTWH(_paddingH, _y, _contentWidth, 0.7 * _scale),
      Paint()..color = const Color(0xFF666666),
    );
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

  TextPainter _measure(
    String text, {
    required double fontSize,
    bool bold = false,
    bool emphasized = false,
    Color color = _black,
    TextAlign align = TextAlign.right,
    double? maxWidth,
  }) {
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

  static String _money(double value) =>
      ReceiptNumberFormat.money(value, currency: 'ج.م');

  static String _qty(double value) => ReceiptNumberFormat.quantity(value);

  static const List<String> _days = <String>[
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
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
    return '$day  $y/$m/$d  $hh:$mm $ampm';
  }

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
  const _Cell(
    this.text, {
    required this.width,
    this.bold = false,
    this.align = TextAlign.right,
  });

  final String text;
  final double width;
  final bool bold;
  final TextAlign align;
}
