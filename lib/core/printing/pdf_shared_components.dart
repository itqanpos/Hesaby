// lib/core/printing/pdf_shared_components.dart
//
// المكونات المشتركة لكل PDF في التطبيق.
// 🔒 الحماية: كل أحجام الخطوط مقيدة بحدود قصوى (hard caps) حتى لا تنفجر
// الصفحة بسبب fontScale مرتفع أو مرور قيمة مكبّرة مسبقاً (double-scaling).

import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show PdfGoogleFonts;

import '../../features/settings/domain/entities/print_style_settings.dart';

// ============================================================================
// Fonts
// ============================================================================

abstract final class PdfSharedFonts {
  static Future<pw.Font>? _regularFuture;
  static Future<pw.Font>? _boldFuture;

  static Future<pw.ThemeData> loadTheme() async {
    final pw.Font regular = await _regular();
    final pw.Font bold = await _bold();
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static Future<pw.Font> _regular() => _regularFuture ??=
      _loadBundledOr('Cairo-Regular.ttf', PdfGoogleFonts.cairoRegular);

  static Future<pw.Font> _bold() => _boldFuture ??=
      _loadBundledOr('Cairo-Bold.ttf', PdfGoogleFonts.cairoBold);

  static Future<pw.Font> _loadBundledOr(
    String fileName,
    Future<pw.Font> Function() fallback,
  ) async {
    try {
      final ByteData data = await rootBundle.load('assets/fonts/$fileName');
      return pw.Font.ttf(data);
    } on Object {
      return fallback();
    }
  }
}

// ============================================================================
// Style (with hard caps)
// ============================================================================

abstract final class PdfSharedStyle {
  /// Absolute maximum size in PDF points. Nothing in the header can exceed
  /// this — protects against `fontScale` set too high in settings, or
  /// against callers accidentally passing a pre-scaled value (double
  /// scaling).
  static const double maxHeaderPointSize = 22.0;

  /// Absolute minimum so text never becomes unreadably tiny.
  static const double minHeaderPointSize = 8.0;

  static pw.FontWeight weight(
    PrintStyleSettings style, {
    bool emphasized = false,
  }) {
    if (emphasized || style.isBoldBase) {
      return pw.FontWeight.bold;
    }
    return pw.FontWeight.normal;
  }

  /// Scaled size with hard clamp (8–22 pt).
  static double size(PrintStyleSettings style, double base) {
    return (base * style.fontScale).clamp(minHeaderPointSize, maxHeaderPointSize);
  }
}

// ============================================================================
// Formatting
// ============================================================================

abstract final class PdfSharedFormat {
  static const String defaultCurrency = 'ج.م';

  static String norm(String input) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final int c = input.codeUnitAt(i);
      switch (c) {
        case 0x0660: out.write('0'); break;
        case 0x0661: out.write('1'); break;
        case 0x0662: out.write('2'); break;
        case 0x0663: out.write('3'); break;
        case 0x0664: out.write('4'); break;
        case 0x0665: out.write('5'); break;
        case 0x0666: out.write('6'); break;
        case 0x0667: out.write('7'); break;
        case 0x0668: out.write('8'); break;
        case 0x0669: out.write('9'); break;
        case 0x066B: out.write('.'); break;
        case 0x066C: out.write(','); break;
        case 0x200E:
        case 0x200F:
        case 0x202A:
        case 0x202B:
        case 0x202C:
        case 0x202D:
        case 0x202E:
          break;
        default:
          out.writeCharCode(c);
      }
    }
    return out.toString();
  }

  static String money(
    double value, {
    String currency = defaultCurrency,
    bool showCurrency = true,
  }) {
    final String num = _groupThousands(value);
    return showCurrency ? '$num $currency' : num;
  }

  static String quantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  static String date(DateTime value) {
    final DateTime local = value.toLocal();
    final String y = local.year.toString().padLeft(4, '0');
    final String m = local.month.toString().padLeft(2, '0');
    final String d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String dayDate(DateTime value) {
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

  static String period(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'من البداية حتى الآن';
    if (from != null && to != null) {
      return 'من ${date(from)} إلى ${date(to)}';
    }
    if (from != null) return 'من ${date(from)}';
    return 'حتى ${date(to!)}';
  }

  static String _groupThousands(double value) {
    final bool negative = value < 0;
    final double abs = value.abs();
    final String raw = abs.toStringAsFixed(2);
    final int dot = raw.indexOf('.');
    final String intPart = dot < 0 ? raw : raw.substring(0, dot);
    final String decPart = dot < 0 ? '' : raw.substring(dot);
    final StringBuffer buf = StringBuffer();
    if (negative) buf.write('-');
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    buf.write(decPart);
    return buf.toString();
  }

  static const List<String> _arabicDays = <String>[
    'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];
}

// ============================================================================
// Title Box (with hard cap)
// ============================================================================

abstract final class PdfSharedTitle {
  static pw.Widget build(
    String title,
    PrintStyleSettings style, {
    double fontSize = 14,
  }) {
    // 🔒 Hard cap — prevents any blow-up (double-scaled or oversized).
    final double safeSize =
        PdfSharedStyle.size(style, fontSize).clamp(10.0, 18.0);

    return pw.Center(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        ),
        child: pw.Text(
          PdfSharedFormat.norm(title),
          style: pw.TextStyle(
            fontSize: safeSize,
            fontWeight: PdfSharedStyle.weight(style, emphasized: true),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Header (all sizes hard-capped)
// ============================================================================

abstract final class PdfSharedHeader {
  static pw.Widget build({
    required String title,
    required PrintStyleSettings style,
    String? companyName,
    String? branchName,
    String? address,
    String? phone,
    String? taxNumber,
    String? commercialRegister,
    String? subtitle,
    Uint8List? logoBytes,
    double logoWidth = 130,
    double titleFontSize = 14,
  }) {
    // Every font here is clamped explicitly — no caller can make the
    // header explode, even if it passes `s.title` (pre-scaled) instead
    // of an unscaled base value.
    final double companySize =
        PdfSharedStyle.size(style, 16).clamp(12.0, 22.0);
    final double smallSize =
        PdfSharedStyle.size(style, 9).clamp(8.0, 12.0);
    final double subtitleSize =
        PdfSharedStyle.size(style, 12).clamp(10.0, 15.0);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: <pw.Widget>[
        if (logoBytes != null && logoBytes.isNotEmpty) ...<pw.Widget>[
          pw.Center(
            child: pw.Image(
              pw.MemoryImage(logoBytes),
              width: logoWidth,
              fit: pw.BoxFit.contain,
            ),
          ),
          pw.SizedBox(height: 6),
        ],
        if (companyName != null && companyName.trim().isNotEmpty) ...<pw.Widget>[
          pw.Center(
            child: pw.Text(
              PdfSharedFormat.norm(companyName),
              style: pw.TextStyle(
                fontSize: companySize,
                fontWeight: PdfSharedStyle.weight(style, emphasized: true),
                letterSpacing: 0.3,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 2),
        ],
        if (address != null && address.trim().isNotEmpty) ...<pw.Widget>[
          pw.Center(
            child: pw.Text(
              PdfSharedFormat.norm(address),
              style: pw.TextStyle(
                fontSize: smallSize,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
        if (phone != null && phone.trim().isNotEmpty) ...<pw.Widget>[
          pw.Center(
            child: pw.Text(
              PdfSharedFormat.norm('هاتف: $phone'),
              style: pw.TextStyle(
                fontSize: smallSize,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
        if (branchName != null && branchName.trim().isNotEmpty) ...<pw.Widget>[
          pw.Center(
            child: pw.Text(
              PdfSharedFormat.norm(branchName),
              style: pw.TextStyle(
                fontSize: smallSize,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
        if (taxNumber != null && taxNumber.trim().isNotEmpty) ...<pw.Widget>[
          pw.Center(
            child: pw.Text(
              PdfSharedFormat.norm('الرقم الضريبي: $taxNumber'),
              style: pw.TextStyle(
                fontSize: smallSize,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
        if (commercialRegister != null && commercialRegister.trim().isNotEmpty) ...<pw.Widget>[
          pw.Center(
            child: pw.Text(
              PdfSharedFormat.norm('السجل التجاري: $commercialRegister'),
              style: pw.TextStyle(
                fontSize: smallSize,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
        pw.SizedBox(height: 8),
        PdfSharedTitle.build(title, style, fontSize: titleFontSize),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              PdfSharedFormat.norm(subtitle),
              style: pw.TextStyle(
                fontSize: subtitleSize,
                fontWeight: PdfSharedStyle.weight(style, emphasized: true),
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
        pw.SizedBox(height: 8),
      ],
    );
  }
}

// ============================================================================
// Footer
// ============================================================================

abstract final class PdfSharedFooter {
  static const String defaultThankYou = 'شكراً لتعاملكم معنا';

  static pw.Widget build(
    pw.Context context,
    PrintStyleSettings style, {
    String? customText,
    bool showPageNumber = true,
  }) {
    final String text = (customText ?? '').trim().isEmpty
        ? defaultThankYou
        : customText!.trim();

    final String pageStr = (showPageNumber && context.pagesCount > 0)
        ? 'صفحة ${context.pageNumber} من ${context.pagesCount}'
        : '';

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Divider(thickness: 0.4, color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                text,
                style: pw.TextStyle(
                  fontSize: PdfSharedStyle.size(style, 8).clamp(6.0, 10.0),
                  color: PdfColors.grey700,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              if (pageStr.isNotEmpty)
                pw.Text(
                  pageStr,
                  style: pw.TextStyle(
                    fontSize: PdfSharedStyle.size(style, 8).clamp(6.0, 10.0),
                    color: PdfColors.grey600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Table
// ============================================================================

abstract final class PdfSharedTable {
  static final pw.TableBorder border = pw.TableBorder.all(
    color: PdfColors.grey700,
    width: 0.5,
  );

  static const pw.BoxDecoration headerDecoration = pw.BoxDecoration(
    color: PdfColors.grey300,
  );

  static pw.BoxDecoration? zebraDecoration(bool isOdd) =>
      isOdd ? const pw.BoxDecoration(color: PdfColors.grey100) : null;

  static const pw.BoxDecoration totalsDecoration = pw.BoxDecoration(
    color: PdfColors.grey200,
  );
}
