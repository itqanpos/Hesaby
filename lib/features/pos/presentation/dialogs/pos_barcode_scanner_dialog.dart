// lib/features/pos/presentation/dialogs/pos_barcode_scanner_dialog.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen barcode scanner dialog.
///
/// The dialog shows a live camera preview and pops with the raw barcode
/// value the moment a code is detected. The cashier can dismiss the screen
/// with the close button or the system back gesture, in which case the
/// dialog resolves with `null`.
///
/// The widget does **not** perform any product lookup. It returns the raw
/// string to its caller, which is responsible for matching it against the
/// catalogue.
class PosBarcodeScannerDialog extends StatefulWidget {
  const PosBarcodeScannerDialog({super.key});

  @override
  State<PosBarcodeScannerDialog> createState() =>
      _PosBarcodeScannerDialogState();
}

class _PosBarcodeScannerDialogState extends State<PosBarcodeScannerDialog> {
  late final MobileScannerController _controller;

  bool _hasEmitted = false;
  Object? _cameraError;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      // Prevent the same barcode from firing multiple times in rapid
      // succession while the dialog is closing.
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  void _handleDetection(BarcodeCapture capture) {
    if (_hasEmitted) {
      return;
    }

    final List<Barcode> barcodes = capture.barcodes;
    for (final Barcode barcode in barcodes) {
      final String? value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _hasEmitted = true;
        Navigator.of(context).pop(value.trim());
        return;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('مسح الباركود'),
        actions: <Widget>[
          IconButton(
            tooltip: 'التبديل للكاميرا الأمامية',
            icon: const Icon(Icons.flip_camera_ios_outlined),
            onPressed: _cameraError != null
                ? null
                : () => _controller.switchCamera(),
          ),
          IconButton(
            tooltip: 'الفلاش',
            icon: const Icon(Icons.flash_on_outlined),
            onPressed: _cameraError != null
                ? null
                : () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          // ---- Camera / error placeholder ----
          Positioned.fill(
            child: _cameraError != null
                ? _CameraErrorView(
                    error: _cameraError!,
                    scheme: scheme,
                  )
               MobileScanner(
  controller: _controller,
  onDetect: _handleDetection,
  errorBuilder: (
    BuildContext context,
    MobileScannerException error,
    Widget? child,
  ) {
    _cameraError = error;
    return _CameraErrorView(error: error, scheme: scheme);
  },
  placeholderBuilder: (
    BuildContext context,
    Widget? child,
  ) =>
      const _LoadingView(),
),
                  ),
          ),

          // ---- Scan guide frame ----
          if (_cameraError == null)
            const IgnorePointer(child: _ScanFrameOverlay()),

          // ---- Hint at the bottom ----
          if (_cameraError == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'وجّه الكاميرا نحو الباركود',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Scan frame overlay
// ============================================================================

class _ScanFrameOverlay extends StatelessWidget {
  const _ScanFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double shortestSide = constraints.biggest.shortestSide;
        final double frameSize =
            shortestSide < 320 ? shortestSide * 0.7 : 280;
        final double cornerLength = frameSize * 0.18;
        const double cornerThickness = 4;

        return Center(
          child: SizedBox(
            width: frameSize,
            height: frameSize,
            child: Stack(
              children: <Widget>[
                // Dimmed background outside the frame
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                        width: 0,
                      ),
                    ),
                  ),
                ),
                // Top-left corner
                Positioned(
                  top: 0,
                  left: 0,
                  child: _Corner(
                    length: cornerLength,
                    thickness: cornerThickness,
                    isTop: true,
                    isLeft: true,
                  ),
                ),
                // Top-right corner
                Positioned(
                  top: 0,
                  right: 0,
                  child: _Corner(
                    length: cornerLength,
                    thickness: cornerThickness,
                    isTop: true,
                    isLeft: false,
                  ),
                ),
                // Bottom-left corner
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: _Corner(
                    length: cornerLength,
                    thickness: cornerThickness,
                    isTop: false,
                    isLeft: true,
                  ),
                ),
                // Bottom-right corner
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: _Corner(
                    length: cornerLength,
                    thickness: cornerThickness,
                    isTop: false,
                    isLeft: false,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Corner extends StatelessWidget {
  const _Corner({
    required this.length,
    required this.thickness,
    required this.isTop,
    required this.isLeft,
  });

  final double length;
  final double thickness;
  final bool isTop;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: length,
      height: length,
      child: CustomPaint(
        painter: _CornerPainter(
          length: length,
          thickness: thickness,
          isTop: isTop,
          isLeft: isLeft,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({
    required this.length,
    required this.thickness,
    required this.isTop,
    required this.isLeft,
  });

  final double length;
  final double thickness;
  final bool isTop;
  final bool isLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final double x = isLeft ? 0 : size.width;
    final double y = isTop ? 0 : size.height;
    final double horizontalEnd = isLeft ? length : size.width - length;
    final double verticalEnd = isTop ? length : size.height - length;

    canvas.drawLine(Offset(x, y), Offset(horizontalEnd, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, verticalEnd), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}

// ============================================================================
// Camera error view
// ============================================================================

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.error, required this.scheme});

  final Object error;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final String message = _messageFor(error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'يمكنك إدخال رقم الباركود يدويًا في حقل البحث.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _messageFor(Object error) {
    if (error is MobileScannerException) {
      switch (error.errorCode) {
        case MobileScannerErrorCode.permissionDenied:
          return 'لم يتم منح صلاحية الكاميرا.';
        case MobileScannerErrorCode.unsupported:
          return 'المسح بالكاميرا غير مدعوم على هذا الجهاز.';
        case MobileScannerErrorCode.controllerUninitialized:
          return 'تعذّر تشغيل الكاميرا.';
        default:
          return 'تعذّر تشغيل الكاميرا.';
      }
    }
    return 'تعذّر تشغيل الكاميرا.';
  }
}

// ============================================================================
// Loading view
// ============================================================================

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
}
