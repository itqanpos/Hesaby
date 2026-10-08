// lib/features/pos/data/services/esc_pos_test_ticket.dart

import 'dart:convert';

/// Builds a minimal ESC/POS ticket used to verify a physical printer
/// connection from the settings page.
///
/// Implemented with raw ESC/POS byte sequences rather than a high-level
/// library, so it has no dependency on the printer package's rendering
/// API and works on every ESC/POS-compatible device.
abstract final class EscPosTestTicket {
  // ESC/POS control sequences (see Epson ESC/POS Command Manual).
  static const List<int> _init = <int>[0x1B, 0x40];             // ESC @
  static const List<int> _alignCenter = <int>[0x1B, 0x61, 0x01]; // ESC a 1
  static const List<int> _alignLeft = <int>[0x1B, 0x61, 0x00];   // ESC a 0
  static const List<int> _boldOn = <int>[0x1B, 0x45, 0x01];      // ESC E 1
  static const List<int> _boldOff = <int>[0x1B, 0x45, 0x00];     // ESC E 0
  static const List<int> _doubleSize = <int>[0x1D, 0x21, 0x11];  // GS ! 0x11
  static const List<int> _normalSize = <int>[0x1D, 0x21, 0x00];  // GS ! 0x00
  static const List<int> _cut = <int>[0x1D, 0x56, 0x42, 0x00];   // GS V B 0
  static const int _lf = 0x0A;

  /// Builds the test ticket bytes.
  static Future<List<int>> build({int mmWidth = 80}) async {
    final List<int> buffer = <int>[];

    buffer.addAll(_init);

    // ---- Header ----
    buffer.addAll(_alignCenter);
    buffer.addAll(_doubleSize);
    buffer.addAll(_boldOn);
    buffer.addAll(_ascii('HESABI'));
    buffer.add(_lf);
    buffer.addAll(_normalSize);
    buffer.addAll(_boldOff);
    buffer.add(_lf);

    buffer.addAll(_ascii('Printer Test / Test Ticket'));
    buffer.add(_lf);
    buffer.add(_lf);

    // ---- Body ----
    buffer.addAll(_alignLeft);
    buffer.addAll(_ascii('--------------------------------'));
    buffer.add(_lf);
    buffer.addAll(_ascii('If you can read this,'));
    buffer.add(_lf);
    buffer.addAll(_ascii('the printer is working.'));
    buffer.add(_lf);
    buffer.addAll(_ascii('--------------------------------'));
    buffer.add(_lf);
    buffer.add(_lf);

    // ---- Footer ----
    buffer.addAll(_alignCenter);
    buffer.addAll(_ascii('Hesabi POS'));
    buffer.add(_lf);
    buffer.add(_lf);
    buffer.add(_lf);

    // ---- Cut ----
    buffer.addAll(_cut);

    return buffer;
  }

  /// Encodes a string as ASCII bytes.
  ///
  /// Only Latin characters are used, so a plain `ascii` encode is safe.
  /// Any character outside the ASCII range would break on printers that
  /// lack the corresponding code page; the test ticket avoids them by
  /// design.
  static List<int> _ascii(String value) => ascii.encode(value);
}
