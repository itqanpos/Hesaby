// lib/features/pos/presentation/dialogs/pos_quick_create_product_dialog.dart

import 'package:flutter/material.dart';

import '../../../products/domain/entities/product.dart';
import '../../../products/presentation/pages/product_form_dialog.dart';

/// Opens the "create product from POS" flow.
///
/// Two steps:
/// 1. A confirmation dialog explaining that no product matched [barcode]
///    (or the search query). The cashier can cancel here.
/// 2. The standard product form dialog, pre-filled with [barcode] when
///    provided.
///
/// Returns the freshly created [Product], or `null` when the cashier
/// cancelled at either step, or when the form was closed without saving.
Future<Product?> showPosQuickCreateProductDialog({
  required BuildContext context,
  String? barcode,
}) async {
  // ---- Step 1: confirmation ----
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => _ConfirmCreateDialog(barcode: barcode),
  );

  if (confirmed != true || !context.mounted) {
    return null;
  }

  // ---- Step 2: product form ----
  Product? created;
  final bool? saved = await showProductFormDialog(
    context: context,
    initialBarcode: barcode,
    onSaved: (Product p) => created = p,
  );

  if (saved != true || created == null) {
    return null;
  }
  return created;
}

// ============================================================================
// Confirmation dialog
// ============================================================================

class _ConfirmCreateDialog extends StatelessWidget {
  const _ConfirmCreateDialog({required this.barcode});

  final String? barcode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasBarcode = barcode != null && barcode!.trim().isNotEmpty;

    return AlertDialog(
      icon: Icon(Icons.help_outline, color: scheme.primary, size: 32),
      title: const Text('منتج غير موجود'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hasBarcode
                ? 'لا يوجد منتج بهذا الباركود في الكتالوج:'
                : 'لا توجد نتائج مطابقة لهذا البحث.',
            style: theme.textTheme.bodyMedium,
          ),
          if (hasBarcode) ...<Widget>[
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.qr_code,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        barcode!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            hasBarcode
                ? 'هل تريد إنشاء منتج جديد بهذا الباركود وإضافته إلى السلة؟'
                : 'هل تريد إنشاء منتج جديد وإضافته إلى السلة؟',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.add),
          label: const Text('إنشاء منتج'),
        ),
      ],
    );
  }
}
