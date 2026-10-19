// lib/features/pos/presentation/dialogs/pos_barcode_scanner_dialog.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/utils/logger.dart';

/// Full-screen barcode scanner dialog — stability-first.
///
/// ## Correctness fixes
/// * **No `scanWindow`** — the previous version passed widget coordinates
///   to `MobileScanner.scanWindow`, which expects **image coordinates**.
///   This mismatch caused native crashes on some Android devices
///   (especially Samsung). The visual overlay is kept as UX only and does
///   not affect detection.
/// * **No `cameraResolution`** — some Android devices reject a hard
///   resolution request at the CameraX level, which crashes the app
///   instead of falling back. Removing it lets the SDK choose a safe
///   default.
/// * Detection paused while the manual-entry sheet is open.
/// * Single owner for camera start; lifecycle-aware.
/// * Torch icon reflects the real state; torch errors are caught.
class PosBarcodeScannerDialog extends StatefulWidget {
  const PosBarcodeScannerDialog({super.key});

  @override
  State<PosBarcodeScannerDialog> createState() =>
      _PosBarcodeScannerDialogState();
}

class _PosBarcodeScannerDialogState extends State<PosBarcodeScannerDialog>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final MobileScannerController _controller;
  late final AnimationController _laserController;

  bool _hasEmitted = false;
  bool _manualOpen = false;
  bool _starting = false;
  bool _isRetrying = false;
  MobileScannerException? _cameraError;

  /// Visual overlay rectangle — widget coordinates, **not** used by the
  /// scanner. Recomputed only when the available size changes.
  Rect? _overlayRect;
  Size? _overlayRectFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = MobileScannerController(
      autoStart: false, // we are the only owner of start()/stop()
      detectionSpeed: DetectionSpeed.unrestricted,
      facing: CameraFacing.back,
      torchEnabled: false,
      // Fewer formats => faster decoding.
      formats: const <BarcodeFormat>[
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
      ],
    );

    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _laserController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_hasEmitted) return;

    if (state == AppLifecycleState.resumed) {
      final MobileScannerException? error = _cameraError;
      if (error == null) {
        _startCamera();
      } else if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
        // User probably came back from the system settings.
        _retry();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller.stop().ignore();
    }
  }

  // ---------------------------------------------------------------------------
  // Camera control
  // ---------------------------------------------------------------------------

  Future<void> _startCamera() async {
    if (_starting || !mounted || _hasEmitted) return;
    _starting = true;
    try {
      await _controller.start();
    } on MobileScannerException catch (error) {
      // Already running is not a real error.
      if (error.errorCode ==
          MobileScannerErrorCode.controllerAlreadyInitialized) {
        return;
      }
      if (mounted) _recordError(error);
    } on Object catch (error, stackTrace) {
      AppLogger.error('Barcode camera start failed', error, stackTrace);
      if (mounted && _cameraError == null) {
        setState(() {
          _cameraError = MobileScannerException(
            errorCode: MobileScannerErrorCode.genericError,
            errorDetails: const MobileScannerErrorDetails(
              message: 'Unknown camera error',
            ),
          );
        });
      }
    } finally {
      _starting = false;
    }
  }

  void _recordError(MobileScannerException error) {
    AppLogger.error(
      'Barcode scanner error: code=${error.errorCode.name} '
      'details=${error.errorDetails?.message ?? "n/a"}',
      error,
    );
    if (mounted && _cameraError == null) {
      setState(() => _cameraError = error);
    }
  }

  Future<void> _retry() async {
    if (_isRetrying) return;

    setState(() {
      _isRetrying = true;
      _cameraError = null;
    });

    try {
      await _controller.stop();
    } on Object {
      // Ignore — the controller may already be stopped.
    }
    if (!mounted) return;

    await _startCamera();
    if (mounted) setState(() => _isRetrying = false);
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } on Object catch (error, stackTrace) {
      AppLogger.error('Torch toggle failed', error, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // Detection
  // ---------------------------------------------------------------------------

  void _handleDetection(BarcodeCapture capture) {
    if (_hasEmitted || _manualOpen) return;

    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw == null) continue;
      final String value = raw.trim();
      if (value.isEmpty) continue;

      _hasEmitted = true;
      HapticFeedback.heavyImpact().ignore();
      SystemSound.play(SystemSoundType.alert).ignore();

      if (mounted) Navigator.of(context).pop(value);
      return;
    }
  }

  Future<void> _manualEntry() async {
    if (_manualOpen || _hasEmitted) return;
    _manualOpen = true;

    final String? value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext ctx) =>
          const _ManualEntrySheet(title: 'إدخال الباركود يدويًا'),
    );

    _manualOpen = false;
    if (value == null || value.trim().isEmpty) return;
    if (!mounted || _hasEmitted) return;
    _hasEmitted = true;
    Navigator.of(context).pop(value.trim());
  }

  // ---------------------------------------------------------------------------
  // Visual overlay rectangle
  // ---------------------------------------------------------------------------

  Rect _overlayRectFor(BoxConstraints constraints) {
    final Size size = constraints.biggest;
    if (_overlayRect != null && _overlayRectFor == size) return _overlayRect!;

    // Barcode-friendly aspect ratio: wider than tall (2:1).
    final double width = (size.width * 0.82).clamp(240.0, 340.0);
    final double height = width * 0.5;
    _overlayRectFor = size;
    return _overlayRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.40),
      width: width,
      height: height,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool hasError = _cameraError != null;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('مسح الباركود'),
        actions: <Widget>[
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (BuildContext context, MobileScannerState state, _) {
              final bool unavailable =
                  state.torchState == TorchState.unavailable;
              final bool on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: 'الفلاش',
                icon: Icon(on ? Icons.flash_on : Icons.flash_off_outlined),
                onPressed: (hasError || unavailable) ? null : _toggleTorch,
              );
            },
          ),
        ],
      ),
      body: hasError
          ? _CameraErrorView(
              error: _cameraError!,
              isRetrying: _isRetrying,
              onRetry: _retry,
              onManualEntry: _manualEntry,
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Rect overlayRect = _overlayRectFor(constraints);

                return Stack(
                  children: <Widget>[
                    // ⬇️ بدون scanWindow — نمسح الصورة بالكامل
                    MobileScanner(
                      controller: _controller,
                      onDetect: _handleDetection,
                      errorBuilder: (
                        BuildContext context,
                        MobileScannerException error,
                        Widget? child,
                      ) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _cameraError == null) {
                            _recordError(error);
                          }
                        });
                        return const _LoadingView();
                      },
                      placeholderBuilder: (
                        BuildContext context,
                        Widget? child,
                      ) =>
                          const _LoadingView(),
                    ),

                    // Static layer: painted once, never repaints.
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _FramePainter(rect: overlayRect),
                        ),
                      ),
                    ),

                    // Animated layer: only the laser line repaints.
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _LaserPainter(
                            rect: overlayRect,
                            animation: _laserController,
                          ),
                        ),
                      ),
                    ),

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
                            icon: const Icon(
                              Icons.keyboard,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'إدخال يدوي',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
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
// Painters
// ============================================================================

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.rect});

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect hole = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    canvas.drawDRRect(
      RRect.fromRectXY(Offset.zero & size, 0, 0),
      hole,
      Paint()..color = const Color(0x99000000),
    );

    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: 0.5),
    );

    const double c = 26;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    final Path corners = Path()
      ..moveTo(rect.left, rect.top + c)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + c, rect.top)
      ..moveTo(rect.right, rect.top + c)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right - c, rect.top)
      ..moveTo(rect.left, rect.bottom - c)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left + c, rect.bottom)
      ..moveTo(rect.right, rect.bottom - c)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - c, rect.bottom);
    canvas.drawPath(corners, p);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.rect != rect;
}

class _LaserPainter extends CustomPainter {
  _LaserPainter({required this.rect, required Animation<double> animation})
      : _animation = animation,
        super(repaint: animation);

  final Rect rect;
  final Animation<double> _animation;

  static const Color _laser = Color(0xFFFF3D00);
  static final Paint _glow = Paint()
    ..color = _laser.withValues(alpha: 0.25)
    ..strokeWidth = 10
    ..strokeCap = StrokeCap.round;
  static final Paint _core = Paint()
    ..color = _laser
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    const double margin = 10;
    final double usable = rect.height - margin * 2;
    final double y = rect.top + margin + usable * _animation.value;
    final Offset a = Offset(rect.left + 8, y);
    final Offset b = Offset(rect.right - 8, y);
    canvas.drawLine(a, b, _glow);
    canvas.drawLine(a, b, _core);
  }

  @override
  bool shouldRepaint(_LaserPainter old) => old.rect != rect;
}

// ============================================================================
// Camera error view
// ============================================================================

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({
    required this.error,
    required this.isRetrying,
    required this.onRetry,
    required this.onManualEntry,
  });

  final Object error;
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
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

  static (String, String) _describe(Object error) {
    if (error is MobileScannerException) {
      switch (error.errorCode) {
        case MobileScannerErrorCode.permissionDenied:
          return (
            'لم يتم منح صلاحية الكاميرا',
            'افتح إعدادات الجهاز ← التطبيقات ← هذا التطبيق ← الأذونات ← '
                'الكاميرا، واختر «السماح». ثم ارجع للتطبيق وسيُعاد التشغيل '
                'تلقائيًا (أو اضغط "إعادة المحاولة").',
          );
        case MobileScannerErrorCode.unsupported:
          return (
            'المسح بالكاميرا غير مدعوم',
            'استخدم قارئ باركود خارجي (HID) أو أدخل الرقم يدويًا.',
          );
        default:
          break;
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
