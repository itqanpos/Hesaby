// lib/features/pos/presentation/services/mobile_scanner_service.dart

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart'
    show BuildContext, MaterialPageRoute, Navigator;

import '../../domain/services/barcode_scanner_service.dart';
import '../dialogs/pos_barcode_scanner_dialog.dart';

/// [BarcodeScannerService] implementation backed by `mobile_scanner`.
///
/// The service delegates the entire user experience to
/// [PosBarcodeScannerDialog], which shows a live camera preview and pops
/// with the raw barcode value when the cashier scans one.
///
/// Platform support:
/// * **Android / iOS** — supported natively by the plugin.
/// * **Web** — supported via the ZXing bridge loaded from `web/index.html`.
/// * **Desktop** (Windows / Linux / macOS) — not supported; callers should
///   hide the scan affordance and rely on HID scanners or manual entry
///   when [isSupported] is `false`.
class MobileScannerServiceImpl implements BarcodeScannerService {
  const MobileScannerServiceImpl();

  @override
  bool get isSupported {
    if (kIsWeb) {
      return true;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Future<String?> scan(BuildContext context) async {
    if (!isSupported) {
      return null;
    }

    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (BuildContext _) => const PosBarcodeScannerDialog(),
      ),
    );
  }
}
