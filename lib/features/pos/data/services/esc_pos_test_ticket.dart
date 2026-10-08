// lib/features/pos/data/services/esc_pos_test_ticket.dart

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// Builds a minimal ESC/POS ticket used to verify a physical printer
/// connection from the settings page.
///
/// The ticket is deliberately simple and contains only Latin characters,
/// so it prints on every thermal printer without needing an Arabic code
/// page. A full Arabic receipt is built elsewhere (Phase D3) via a
/// raster pipeline.
abstract final class EscPosTestTicket {
  /// Builds the test ticket for an 80 mm (or 58 mm) roll.
  ///
  /// The [mmWidth] is only used to pick a paper profile; the actual print
  /// width is decided by the printer's paper sensor.
  static Future<List<int>> build({int mmWidth = 80}) async {
    final CapabilityProfile profile = await CapabilityProfile.load();
    final PaperSize size =
        mmWidth == 58 ? PaperSize.mm58 : PaperSize.mm80;
    final Generator generator = Generator(size, profile);

    generator.text(
      'Hesabi',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    generator.feed(1);
    generator.text(
      'Printer test / اختبار الطابعة',
      styles: const PosStyles(align: PosAlign.center),
    );
    generator.hr();
    generator.text('If you can read this,');
    generator.text('the printer is working.');
    generator.feed(1);
    generator.text(
      'Hesabi POS',
      styles: const PosStyles(align: PosAlign.center),
    );
    generator.feed(3);
    generator.cut();

    return generator.getBytes();
  }
}
