// lib/features/purchases/presentation/widgets/thermal_purchase_preview.dart

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../../pos/data/services/pos_preferences.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/esc_pos_purchase_receipt_builder.dart';
import '../../domain/entities/purchase_receipt.dart';

/// Live WYSIWYG preview of the thermal purchase receipt.
///
/// Renders the **exact same bitmap** that
/// [EscPosPurchaseReceiptBuilder] sends to the printer, so what the user
/// sees in this widget matches the printed output 1:1 (same fonts, same
/// column layout, same logo placement).
///
/// The bitmap is re-rendered whenever [receipt] or [paperSize] changes.
/// The image is displayed inside a white "paper" frame with a subtle
/// shadow, scaled to fit the parent width while preserving aspect ratio.
class ThermalPurchasePreview extends ConsumerStatefulWidget {
  const ThermalPurchasePreview({
    super.key,
    required this.receipt,
    required this.paperSize,
    this.maxHeight,
  });

  final PurchaseReceipt receipt;

  /// Selected paper size, controlled by the parent dialog.
  final ReceiptPaperSize paperSize;

  /// Optional clamp on the preview height. When null, uses the intrinsic
  /// bitmap height.
  final double? maxHeight;

  @override
  ConsumerState<ThermalPurchasePreview> createState() =>
      _ThermalPurchasePreviewState();
}

class _ThermalPurchasePreviewState
    extends ConsumerState<ThermalPurchasePreview> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _renderPng();
  }

  @override
  void didUpdateWidget(ThermalPurchasePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipt != widget.receipt ||
        oldWidget.paperSize != widget.paperSize) {
      setState(() {
        _future = _renderPng();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  Future<Uint8List?> _renderPng() async {
    try {
      final int widthDots = _widthDotsFor(widget.paperSize);
      final Uint8List? logoBytes = await _loadLogoBytes();
      final PrintStyleSettings style = _readStyle();

      final ui.Image image =
          await EscPosPurchaseReceiptBuilder.renderToImage(
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
      AppLogger.error('Thermal purchase preview render failed', e, st);
      return null;
    }
  }

  static int _widthDotsFor(ReceiptPaperSize size) {
    switch (size) {
      case ReceiptPaperSize.mm58:
        return EscPosPurchaseReceiptBuilder.widthMm58;
      case ReceiptPaperSize.mm80:
      case ReceiptPaperSize.a4:
        return EscPosPurchaseReceiptBuilder.widthMm80;
    }
  }

  PrintStyleSettings _readStyle() {
    final CompanySettings? s =
        ref.read(companySettingsProvider).valueOrNull;
    if (s == null) return const PrintStyleSettings.defaults();
    if (widget.paperSize == ReceiptPaperSize.a4) {
      return PrintStyleSettings(
        fontScale: s.printFontScaleA4,
        fontWeight: s.printFontWeight,
      );
    }
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

            final Widget image = Image.memory(
              bytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            );

            if (widget.maxHeight != null) {
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxHeight!),
                child: image,
              );
            }
            return image;
          },
        ),
      ),
    );
  }
}
