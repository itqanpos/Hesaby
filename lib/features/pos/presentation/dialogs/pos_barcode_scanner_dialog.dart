// lib/features/pos/presentation/dialogs/pos_barcode_scanner_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen barcode scanner dialog.
///
/// The dialog shows a live camera preview and pops with the raw barcode
/// value the moment a code is detected. The cashier can dismiss the screen
/// with the close button or the system back gesture, in which case the
/// dialog resolves with `null`.
///
/// Fallbacks when the camera is unavailable (permission denied, unsupported
/// browser, no camera):
/// * **إعادة المحاولة** — calls `controller.start()` again. Useful when
///   the user has just granted permission or fixed the browser settings.
/// * **إدخال يدوي** — opens a small text field so the cashier can type the
///   barcode; the dialog pops with that value.
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
  MobileScannerException? _cameraError;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
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

    for (final Barcode barcode in capture.barcodes) {
      final String? value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _hasEmitted = true;
        Navigator.of(context).pop(value.trim());
        return;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Fallbacks
  // ---------------------------------------------------------------------------

  Future<void> _retry() async {
    if (_isRetrying) return;

    setState(() {
      _isRetrying = true;
      _cameraError = null;
    });

    try {
      await _controller.stop();
    } on Object {
      // Ignore: the controller may not be running.
    }

    try {
      await _controller.start();
    } on MobileScannerException catch (error) {
      if (mounted) {
        setState(() => _cameraError = error);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _cameraError = MobileScannerException(
            errorCode: MobileScannerErrorCode.unknown,
            errorDetails: const MobileScannerErrorDetails(
              message: 'Unknown camera error',
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  Future<void> _manualEntry() async {
    final String? value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => _ManualEntrySheet(
        title: 'إدخال الباركود يدويًا',
      ),
    );
    if (value == null || value.trim().isEmpty) {
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(value.trim());
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool hasError = _cameraError != null;

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
            onPressed: hasError ? null : () => _controller.switchCamera(),
          ),
          IconButton(
            tooltip: 'الفلاش',
            icon: const Icon(Icons.flash_on_outlined),
            onPressed: hasError ? null : () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _buildScannerArea(scheme),
          ),
          if (!hasError) ...<Widget>[
            const IgnorePointer(child: _ScanFrameOverlay()),
            const _BottomHint(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 88,
              child: SafeArea(
                top: false,
                child: Center(
                  child: TextButton.icon(
                    onPressed: _manualEntry,
                    icon: const Icon(Icons.keyboard, color: Colors.white),
                    label: const Text(
                      'إدخال يدوي',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScannerArea(ColorScheme scheme) {
    if (_cameraError != null) {
      return _CameraErrorView(
        error: _cameraError!,
        scheme: scheme,
        isRetrying: _isRetrying,
        onRetry: _retry,
        onManualEntry: _manualEntry,
      );
    }

    return MobileScanner(
      controller: _controller,
      onDetect: _handleDetection,
      errorBuilder: (
        BuildContext context,
        MobileScannerException error,
        Widget? child,
      ) {
        // Schedule a state update for the next frame so the AppBar actions
        // reflect the error state. We cannot call setState synchronously
        // inside the builder without triggering a reentrant build.
        if (_cameraError == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _cameraError == null) {
              setState(() => _cameraError = error);
            }
          });
        }
        return _CameraErrorView(
          error: error,
          scheme: scheme,
          isRetrying: _isRetrying,
          onRetry: _retry,
          onManualEntry: _manualEntry,
        );
      },
      placeholderBuilder: (
        BuildContext context,
        Widget? child,
      ) =>
          const _LoadingView(),
    );
  }
}

// ============================================================================
// Bottom hint
// ============================================================================

class _BottomHint extends StatelessWidget {
  const _BottomHint();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 32,
      child: SafeArea(
        top: false,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
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
  const _CameraErrorView({
    required this.error,
    required this.scheme,
    required this.isRetrying,
    required this.onRetry,
    required this.onManualEntry,
  });

  final Object error;
  final ColorScheme scheme;
  final bool isRetrying;
  final VoidCallback onRetry;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    final (String title, String hint) = _describe(error);

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
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
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: isRetrying ? null : onRetry,
                    icon: isRetrying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onManualEntry,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('إدخال يدوي'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Error description
  // ---------------------------------------------------------------------------

  static (String, String) _describe(Object error) {
    if (error is MobileScannerException) {
      switch (error.errorCode) {
        case MobileScannerErrorCode.permissionDenied:
          return (
            'لم يتم منح صلاحية الكاميرا',
            'لتشغيل الكاميرا:\n'
                '• في Chrome: اضغط أيقونة القفل بجانب العنوان ← الأذونات ← الكاميرا ← السماح.\n'
                '• في Safari: الإعدادات ← Safari ← الكاميرا ← اسأل/السماح.\n'
                '• بعد التفعيل، ارجع هنا واضغط "إعادة المحاولة".',
          );
        case MobileScannerErrorCode.unsupported:
          return (
            'المسح بالكاميرا غير مدعوم',
            'استخدم قارئ باركود خارجي (HID) أو أدخل الرقم يدويًا.',
          );
        case MobileScannerErrorCode.controllerUninitialized:
          return (
            'تعذّر تشغيل الكاميرا',
            'حاول مرة أخرى، أو أدخل الرقم يدويًا.',
          );
        default:
          return (
            'تعذّر تشغيل الكاميرا',
            'حاول مرة أخرى، أو أدخل الرقم يدويًا.',
          );
      }
    }
    return (
      'تعذّر تشغيل الكاميرا',
      'حاول مرة أخرى، أو أدخل الرقم يدويًا.',
    );
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

// ============================================================================
// Manual entry sheet
// ============================================================================

class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet({required this.title});

  final String title;

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.keyboard, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.text,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'رقم الباركود',
                hintText: 'مثال: 6221031001234',
                prefixIcon: Icon(Icons.qr_code),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
  }
}
