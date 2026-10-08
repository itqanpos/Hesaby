// lib/features/pos/data/services/esc_pos_receipt_builder.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/receipt.dart';

/// Builds an ESC/POS byte stream from a [Receipt] by rendering the whole
/// document as a 1-bit bitmap and sending it as a `GS v 0` raster command.
///
/// Rationale: most budget thermal printers (Xprinter, Goojprt, etc.) do
/// not implement an Arabic code page, so sending Arabic text as ESC/POS
/// bytes prints garbage. Rasterising the receipt guarantees the output
/// matches what the user sees, at the cost of a slightly slower transfer.
///
/// The layout mirrors `PdfReceiptBuilder` visually: same sections, same
/// column order, same formatting — just drawn in raw pixels.
abstract final class EscPosReceiptBuilder {
  // ---- ESC/POS control sequences ----
  static const List<int> _init = <int>[0x1B, 0x40]; // ESC @ (initialize)
  static const List<int> _feedAndCut = <int>[
    0x1B, 0x64, 0x04, // ESC d 4  (feed 4 lines)
    0x1D, 0x56, 0x42, 0x00, // GS V B 0 (partial cut)
  ];

  // ---- Paper widths, in dots at 203 DPI ----
  /// 80 mm roll — 576 dots wide (72 mm printable).
  static const int widthMm80 = 576;

  /// 58 mm roll — 384 dots wide (48 mm printable).
  static const int widthMm58 = 384;

  // ---- Font family names, resolved once from google_fonts ----
  static String? _regularFamily;
  static String? _boldFamily;

  /// Builds the full ESC/POS byte stream for [receipt].
  ///
  /// [paperWidthDots] must be [widthMm80] or [widthMm58].
  static Future<List<int>> build({
    required Receipt receipt,
    int paperWidthDots = widthMm80,
  }) async {
    await _ensureFonts();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);

    final _Painter painter = _Painter(
      canvas: canvas,
      paperWidthDots: paperWidthDots,
      regularFamily: _regularFamily!,
      boldFamily: _boldFamily!,
    );
    painter.paint(receipt);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(
      paperWidthDots,
      painter.totalHeight.ceil(),
    );
    picture.dispose();

    final List<int> raster = await _encodeRaster(image);
    image.dispose();

    return <int>[
      ..._init,
      ...raster,
      ..._feedAndCut,
    ];
  }

  // ---------------------------------------------------------------------------
  // Fonts
  // ---------------------------------------------------------------------------

  /// Loads Cairo (Regular + Bold) into the engine so the canvas can
  /// render Arabic glyphs. Idempotent.
  static Future<void> _ensureFonts() async {
    if (_regularFamily != null && _boldFamily != null) return;

    final TextStyle regular = GoogleFonts.cairo();
    final TextStyle bold =
        GoogleFonts.cairo(fontWeight: FontWeight.w700);

    await GoogleFonts.pendingFonts(<TextStyle>[regular, bold]);

    _regularFamily = regular.fontFamily ?? 'Cairo';
    _boldFamily = bold.fontFamily ?? 'Cairo';
  }

  // ---------------------------------------------------------------------------
  // Raster encoding
  // ---------------------------------------------------------------------------

  /// Converts a rendered [ui.Image] into a `GS v 0` raster command.
  ///
  /// Each byte encodes 8 horizontal pixels, MSB leftmost. A pixel is
  /// considered black when its luminance is below [threshold].
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
          if (a < 128) continue; // transparent = white
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

    // GS v 0 m xL xH yL yH d1...dk
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

/// Draws a [Receipt] on a canvas at `paperWidthDots × variable height`.
///
/// Everything scales with `paperWidthDots / 576` so the same code works
/// for 80 mm and 58 mm rolls. The painter tracks the vertical cursor and
/// exposes [totalHeight] once painting is done.
class _Painter {
  _Painter({
    required this.canvas,
    required this.paperWidthDots,
    required this.regularFamily,
    required this.boldFamily,
  }) : _scale = paperWidthDots / 576.0;

  final ui.Canvas canvas;
  final int paperWidthDots;
  final String regularFamily;
  final String boldFamily;
  final double _scale;

  double _y = 0;

  static const Color _black = Color(0xFF000000);
  static const Color _grey = Color(0xFF444444);

  double get _paddingTop => 12 * _scale;
  double get _paddingBottom => 16 * _scale;
  double get _paddingH => 14 * _scale;
  double get _sectionGap => 8 * _scale;
  double get _contentWidth => paperWidthDots - 2 * _paddingH;
  double get totalHeight => _y + _paddingBottom;

  // ---------------------------------------------------------------------------
  // Entry
  // ---------------------------------------------------------------------------

  void paint(Receipt r) {
    _y = _paddingTop;

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

  // ---------------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------------

  void _header(Receipt r) {
    _text(
      r.companyName,
      fontSize: 24,
      bold: true,
      align: TextAlign.center,
    );
    _gap(2 * _scale);
    _text(
      r.branchName,
      fontSize: 15,
      color: _grey,
      align: TextAlign.center,
    );
    _gap(_sectionGap);
    _chip('فاتورة مبيعات', fontSize: 17);
  }

  void _meta(Receipt r) {
    _metaRow('رقم الفاتورة', r.invoiceNumber ?? '—', bold: true);
    _metaRow('التاريخ', _formatDayAndDate(r.dateTime));
    if (r.hasCustomer) {
      _metaRow('العميل', r.customerName!);
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

    // Header row
    _row(
      cells: <_Cell>[
        _Cell('الإجمالي',
            width: colTotalW, bold: true, align: TextAlign.center),
        _Cell('السعر',
            width: colPriceW, bold: true, align: TextAlign.center),
        _Cell('الكمية',
            width: colQtyW, bold: true, align: TextAlign.center),
        _Cell('الصنف',
            width: colNameW, bold: true, align: TextAlign.right),
        _Cell('م',
            width: colNumW, bold: true, align: TextAlign.center),
      ],
      fontSize: 13,
      topPad: 6 * _scale,
      bottomPad: 6 * _scale,
      backgroundColor: const Color(0xFFDDDDDD),
    );

    // Item rows
    for (int i = 0; i < r.lines.length; i++) {
      final ReceiptLine line = r.lines[i];
      final Color? bg = i.isOdd ? const Color(0xFFF2F2F2) : null;
      _row(
        cells: <_Cell>[
          _Cell(_money(line.lineTotal),
              width: colTotalW, bold: true, align: TextAlign.center),
          _Cell(_money(line.unitPrice),
              width: colPriceW, align: TextAlign.center),
          _Cell('${_qty(line.quantity)} ${line.unitName}',
              width: colQtyW, align: TextAlign.center),
          _Cell(line.productName,
              width: colNameW, align: TextAlign.right),
          _Cell('${i + 1}',
              width: colNumW, align: TextAlign.center),
        ],
        fontSize: 13,
        topPad: 5 * _scale,
        bottomPad: 5 * _scale,
        backgroundColor: bg,
      );
    }

    // Subtotal row
    _row(
      cells: <_Cell>[
        _Cell(_money(r.subtotal),
            width: colTotalW, bold: true, align: TextAlign.center),
        _Cell('', width: colPriceW, align: TextAlign.center),
        _Cell('${r.lines.length}',
            width: colQtyW, align: TextAlign.center),
        _Cell('المجموع الفرعي',
            width: colNameW, bold: true, align: TextAlign.right),
        _Cell('', width: colNumW, align: TextAlign.center),
      ],
      fontSize: 13,
      topPad: 6 * _scale,
      bottomPad: 6 * _scale,
      backgroundColor: const Color(0xFFE8E8E8),
    );
  }

  void _grandTotal(Receipt r) {
    const double fontSize = 20;
    final double boxPad = 8 * _scale;

    final TextPainter label = _measure(
      'إجمالي الفاتورة',
      fontSize: fontSize,
      bold: true,
    );
    final TextPainter value = _measure(
      _money(r.total),
      fontSize: fontSize,
      bold: true,
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

    label.paint(canvas, Offset(_paddingH + boxPad, _y + boxPad));
    value.paint(
      canvas,
      Offset(
        _paddingH + _contentWidth - boxPad - value.width,
        _y + boxPad,
      ),
    );

    _y += boxH;
  }

  void _paymentBlock(Receipt r) {
    final double remaining = r.total - r.paidAmount;
    final double amountRemaining = remaining > 0 ? remaining : 0;

    _kvRow('طريقة الدفع', _paymentMethodLabel(r));
    _kvRow('المدفوع', _money(r.paidAmount));
    if (amountRemaining > 0) {
      _kvRow('المتبقي على العميل', _money(amountRemaining),
          emphasized: true);
    }
    if (r.hasChange) {
      _kvRow('الباقي للعميل', _money(r.change));
    }
  }

  void _balanceBlock(Receipt r) {
    _kvRow('الرصيد السابق', _money(r.previousBalance ?? 0));
    if (r.hasBalancePayment) {
      _kvRow('مدفوع على الرصيد السابق', _money(r.paidOnBalance));
    }
    _kvRow('الرصيد الحالي', _money(r.newBalance ?? 0),
        emphasized: true);
  }

  void _footer(Receipt r) {
    _text(
      _footerText(r),
      fontSize: 14,
      color: _grey,
      align: TextAlign.center,
    );
  }

  // ---------------------------------------------------------------------------
  // Building blocks
  // ---------------------------------------------------------------------------

  void _metaRow(String label, String value, {bool bold = false}) {
    final double labelW = 92 * _scale;
    const double fontSize = 14;

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
    const double labelFont = 14;
    final double valueFont = emphasized ? 17 : 14;

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

    labelPainter.paint(canvas, Offset(_paddingH, _y));
    valuePainter.paint(
      canvas,
      Offset(_paddingH + _contentWidth - valuePainter.width, _y),
    );

    _y += rowH + 3 * _scale;
  }

  void _text(
    String text, {
    required double fontSize,
    bool bold = false,
    Color color = _black,
    TextAlign align = TextAlign.right,
  }) {
    final TextPainter painter = _measure(
      text,
      fontSize: fontSize,
      bold: bold,
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
      bold: true,
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

    // RTL column order: first cell on the right.
    double x = _paddingH + _contentWidth;
    for (int i = 0; i < cells.length; i++) {
      final _Cell cell = cells[i];
      x -= cell.width;
      final TextPainter painter = painters[i];
      final double contentY = _y + topPad + (maxH - painter.height) / 2;
      painter.paint(canvas, Offset(x + 2 * _scale, contentY));
    }

    // Bottom border of the row
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

  // ---------------------------------------------------------------------------
  // Dividers & gaps
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Measurement
  // ---------------------------------------------------------------------------

  TextPainter _measure(
    String text, {
    required double fontSize,
    bool bold = false,
    Color color = _black,
    TextAlign align = TextAlign.right,
    double? maxWidth,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize * _scale,
          color: color,
          fontFamily: bold ? boldFamily : regularFamily,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: align,
    );
    painter.layout(maxWidth: maxWidth ?? _contentWidth);
    return painter;
  }

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
    return '$number ج.م';
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
