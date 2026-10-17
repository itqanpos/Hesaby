// lib/features/pos/presentation/widgets/thermal_receipt_preview.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/esc_pos_receipt_builder.dart';
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../domain/entities/receipt.dart';

/// Live WYSIWYG preview of the thermal receipt.
///
/// Renders the **exact same bitmap** that [EscPosReceiptBuilder] sends to
/// the printer, so what the user sees in this widget matches the printed
/// output 1:1 (same fonts, same column layout, same logo placement).
///
/// The bitmap is re-rendered whenever the [receipt] changes, or when a
/// new dialog instance mounts.
///
/// The image is displayed inside a white "paper" frame with a subtle
/// shadow, and is scaled to fit the parent width while preserving aspect
/// ratio.
class ThermalReceiptPreview extends ConsumerStatefulWidget {
  const ThermalReceiptPreview({
    super.key,
    required this.receipt,
    this.maxHeight,
  });

  final Receipt receipt;

  /// Optional clamp on the preview height. When null, uses the intrinsic
  /// bitmap height.
  final double? maxHeight;

  @override
  ConsumerState<ThermalReceiptPreview> createState() =>
      _ThermalReceiptPreviewState();
}

class _ThermalReceiptPreviewState
    extends ConsumerState<ThermalReceiptPreview> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _renderPng();
  }

  @override
  void didUpdateWidget(ThermalReceiptPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipt != widget.receipt) {
      setState(() {
        _future = _renderPng();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  /// Display zoom of the receipt: 100% fits the viewer width, up to 200%.
  double _zoom = 1.0;

  void _zoomIn() => setState(() => _zoom = (_zoom + 0.25).clamp(1.0, 2.0));

  void _zoomOut() => setState(() => _zoom = (_zoom - 0.25).clamp(1.0, 2.0));

  Future<Uint8List?> _renderPng() async {
    try {
      final int widthDots = _resolveWidthDots();
      final Uint8List? logoBytes = await _loadLogoBytes();
      final PrintStyleSettings style = _readStyle();

      final ui.Image image = await EscPosReceiptBuilder.renderToImage(
        receipt: widget.receipt,
        paperWidthDots: widthDots,
        logoBytes: logoBytes,
        fontScale: style.fontScale,
        fontWeight: style.fontWeight,
      );
      try {
        final ByteData? data =
            await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } on Object catch (e, st) {
      AppLogger.error('Thermal preview render failed', e, st);
      return null;
    }
  }

  int _resolveWidthDots() {
    final ReceiptPaperSize size =
        ref.read(posPaperSizeProvider).valueOrNull ??
            PosPreferences.defaultPaperSize;
    return switch (size) {
      ReceiptPaperSize.mm58 => EscPosReceiptBuilder.widthMm58,
      ReceiptPaperSize.mm80 ||
      ReceiptPaperSize.a4 =>
        EscPosReceiptBuilder.widthMm80,
    };
  }

  PrintStyleSettings _readStyle() {
    final CompanySettings? s =
        ref.read(companySettingsProvider).valueOrNull;
    if (s == null) return const PrintStyleSettings.defaults();
    return PrintStyleSettings.fromCompanySettings(s);
  }

  Future<Uint8List?> _loadLogoBytes() async {
    final CompanySettings? s =
        ref.read(companySettingsProvider).valueOrNull;
    if (s == null || s.companyId.isEmpty) return null;
    try {
      return await const CompanyLogoLoader().load(
        companyId: s.companyId,
        logoUrl: s.logoUrl,
      );
    } on Object catch (e) {
      AppLogger.warning('Logo load failed (non-fatal): $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: FutureBuilder<Uint8List?>(
          future: _future,
          builder: (BuildContext context, AsyncSnapshot<Uint8List?> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final Uint8List? bytes = snap.data;
            if (bytes == null) {
              return const SizedBox(
                height: 140,
                child: Center(child: Text('تعذّر تحميل المعاينة.')),
              );
            }

            return _ReceiptViewer(
              bytes: bytes,
              zoom: _zoom,
              height: widget.maxHeight ?? 480,
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
            );
          },
        ),
      ),
    );
  }
}

/// Scrollable receipt: the full receipt is shown at a readable size and can
/// be scrolled vertically, and horizontally when zoomed in.
class _ReceiptViewer extends StatelessWidget {
  const _ReceiptViewer({
    required this.bytes,
    required this.zoom,
    required this.height,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final Uint8List bytes;
  final double zoom;
  final double height;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: 'تصغير',
              onPressed: zoom <= 1.0 ? null : onZoomOut,
              icon: const Icon(Icons.zoom_out),
            ),
            Expanded(
              child: Text(
                '${(zoom * 100).round()}%',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge,
              ),
            ),
            IconButton(
              tooltip: 'تكبير',
              onPressed: zoom >= 2.0 ? null : onZoomIn,
              icon: const Icon(Icons.zoom_in),
            ),
          ],
        ),
        SizedBox(
          height: height,
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget image = Image.memory(
                  bytes,
                  width: constraints.maxWidth * zoom,
                  fit: BoxFit.fitWidth,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: image,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
