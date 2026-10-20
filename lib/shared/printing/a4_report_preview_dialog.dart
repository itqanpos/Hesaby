// lib/shared/printing/a4_report_preview_dialog.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// نافذة مخصصة للتقارير الطويلة وكشوف الحسابات (A4)
Future<void> showA4ReportPreviewDialog({
  required BuildContext context,
  required String title,
  required Uint8List pdfBytes,
  required String filename,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: PdfPreview(
              build: (format) => pdfBytes,
              allowPrinting: true,
              allowSharing: true,
              canChangePageFormat: false,
              canChangeOrientation: false,
              pdfFileName: filename,
              loadingWidget: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    ),
  );
}
