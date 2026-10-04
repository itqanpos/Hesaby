// lib/features/pos/domain/services/barcode_scanner_service.dart

import 'package:flutter/widgets.dart';

/// Contract for a barcode scanning service used by the POS.
///
/// The POS presents a scanner entry point to the cashier. The concrete
/// implementation may be:
///
/// * a camera-based scanner using the device's camera (mobile / web),
/// * a system-provided scanner (Android / iOS intent),
/// * a purely textual input fallback when no camera is available.
///
/// USB and Bluetooth HID scanners are **not** modelled here. Those devices
/// behave like keyboards: they type the barcode into the focused text field
/// and press Enter. That flow is handled directly by the search field and
/// does not require a service implementation.
///
/// Notes on the `BuildContext` parameter
/// -------------------------------------
/// This contract is intentionally declared under `domain/services/`, yet it
/// depends on [BuildContext]. The general rule "Domain must not depend on
/// Flutter" protects business logic. A scanner is not business logic: it is
/// a UI coordination point that opens a camera dialog and returns a string.
/// Accepting [BuildContext] directly is the pragmatic Flutter way to open a
/// dialog without introducing an extra indirection layer, and it keeps the
/// API predictable for the widget that calls it.
abstract interface class BarcodeScannerService {
  /// Opens the scanner UI attached to [context] and resolves with the
  /// scanned barcode, or `null` when the cashier dismisses the scanner or
  /// no barcode was detected.
  ///
  /// The returned string is **raw** — no validation, no normalisation, no
  /// database lookup. Callers are responsible for deciding what to do with
  /// it.
  Future<String?> scan(BuildContext context);

  /// Whether this platform supports an in-app camera scanner.
  ///
  /// Callers use this flag to decide whether to show a "scan" affordance.
  /// When `false`, they should fall back to manual entry and to HID
  /// scanners. Implementations that rely on platform features unavailable
  /// on the current target must return `false`.
  bool get isSupported;
}
