// lib/features/pos/presentation/widgets/pos_actions_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/presentation/dialogs/customer_payment_dialog.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../../sales/presentation/pages/sale_return_form_page.dart'; // ⬅️ استيراد شاشة المرتجع الجديدة
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../domain/entities/pos_cart.dart';
import '../dialogs/pos_print_settings_sheet.dart';
import '../state/pos_providers.dart';

/// Opens the POS actions menu.
Future<void> showPosActionsSheet({required BuildContext context}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => const _PosActionsSheet(),
  );
}

// ⬇️ مزود لحالة السلة المعلقة (في الذاكرة مؤقتاً)
final heldCartProvider = StateProvider<PosCart?>((ref) => null);

class _PosActionsSheet extends ConsumerWidget {
  const _PosActionsSheet();

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final PosCart cart = ref.watch(posCartProvider);
    final String? customerName = cart.customerName;
    final PosCart? heldCart = ref.watch(heldCartProvider);

    final AsyncValue<ReceiptPaperSize> asyncSize =
        ref.watch(posPaperSizeProvider);
    final ReceiptPaperSize currentSize = asyncSize.valueOrNull ??
        PosPreferences.defaultPaperSize;

    final bool canCollect =
        customerName != null && cart.customerBalance > 0;
    final String collectSubtitle;
    if (customerName == null) {
      collectSubtitle = 'يتطلب اختيار عميل أولًا';
    } else if (cart.customerBalance <= 0) {
      collectSubtitle = 'لا يوجد رصيد مستحق على $customerName';
    } else {
      collectSubtitle =
          'الرصيد الحالي: ${_money.format(cart.customerBalance)}';
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'خيارات',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),

            if (customerName != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'العميل المحدد: $customerName',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            _ActionTile(
              icon: Icons.payments_outlined,
              title: 'تحصيل من العميل',
              subtitle: collectSubtitle,
              enabled: canCollect,
              onTap: () => _openCustomerPayment(context, ref, cart),
            ),
            _ActionTile(
              icon: Icons.print_outlined,
              title: 'إعدادات الطباعة',
              subtitle: 'مقاس الورق الحالي: ${_labelOf(currentSize)}',
              enabled: true,
              onTap: () => _openPrintSettings(context),
            ),
            _ActionTile(
              icon: Icons.pause_circle_outline,
              title: 'تعليق الفاتورة',
              subtitle: 'حفظ السلة مؤقتاً وبدء سلة جديدة.',
              enabled: cart.isNotEmpty,
              onTap: () => _holdCart(context, ref),
            ),
            _ActionTile(
              icon: Icons.shopping_bag_outlined,
              title: 'استعادة السلة',
              subtitle: heldCart != null
                  ? 'استعادة السلة المعلقة (${heldCart.lines.length} صنف).'
                  : 'لا توجد سلة معلقة.',
              enabled: heldCart != null,
              onTap: () => _restoreCart(context, ref),
            ),

            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),

            _ActionTile(
              icon: Icons.receipt_long_outlined,
              title: 'الفاتورة الحالية',
              subtitle: 'مراجعة بنود الفاتورة الحالية',
              enabled: cart.isNotEmpty,
              onTap: () => _viewCurrentReceipt(context, ref),
            ),
            _ActionTile(
              icon: Icons.history_outlined,
              title: 'إعادة طباعة الإيصال',
              subtitle: 'طباعة آخر إيصال مكتمل',
              enabled: true,
              onTap: () => _reprintLastReceipt(context, ref),
            ),
            _ActionTile(
              icon: Icons.assignment_return_outlined,
              title: 'إنشاء فاتورة مرتجع',
              subtitle: 'إرجاع أي صنف إلى المخزون', // ⬅️ تم تعديل النص الفرعي
              enabled: true,
              onTap: () => _openReturns(context),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 10),

            Text(
              'الحفظ يُطبق على الجلسة الحالية فقط.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _openPrintSettings(BuildContext context) {
    Navigator.of(context).pop();
    showPosPrintSettingsSheet(context: context);
  }

  Future<void> _openCustomerPayment(
    BuildContext context,
    WidgetRef ref,
    PosCart cart,
  ) async {
    final String? customerId = cart.customerId;
    final String? customerName = cart.customerName;
    if (customerId == null || customerName == null) {
      return;
    }

    final Customer? updated = await showCustomerPaymentDialog(
      context: context,
      customerId: customerId,
      customerName: customerName,
      currentBalance: cart.customerBalance,
    );

    if (updated == null || !context.mounted) {
      return;
    }

    ref.read(posCartProvider.notifier).updateCustomerBalance(updated.balance);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('تم تسجيل الدفعة بنجاح.')),
      );
  }

  /// يحفظ السلة الحالية في `heldCartProvider` ثم يفرغ السلة.
  void _holdCart(BuildContext context, WidgetRef ref) {
    final cart = ref.read(posCartProvider);
    ref.read(heldCartProvider.notifier).state = cart;
    ref.read(posCartProvider.notifier).reset();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تعليق الفاتورة.')),
    );
  }

  /// يستعيد السلة المعلقة.
  void _restoreCart(BuildContext context, WidgetRef ref) {
    final heldCart = ref.read(heldCartProvider);
    if (heldCart == null) return;
    ref.read(posCartProvider.notifier).restore(heldCart);
    ref.read(heldCartProvider.notifier).state = null;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم استعادة السلة المعلقة.')),
    );
  }

  Future<void> _viewCurrentReceipt(BuildContext context, WidgetRef ref) async {
    final cart = ref.read(posCartProvider);
    if (cart.isEmpty) return;

    Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بنود الفاتورة الحالية'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: cart.lines.length,
            itemBuilder: (ctx, i) {
              final line = cart.lines[i];
              return ListTile(
                title: Text(line.productName),
                subtitle: Text(
                  '${_money.format(line.unitPrice)} × ${line.quantity} ${line.unitName}',
                ),
                trailing: Text(_money.format(line.lineTotal)),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _reprintLastReceipt(BuildContext context, WidgetRef ref) async {
    final salesAsync = ref.read(salesProvider);
    final sales = salesAsync.valueOrNull;
    if (sales == null || sales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد فواتير سابقة.')),
      );
      return;
    }

    final lastSale = sales.first;
    Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('آخر إيصال'),
        content: Text(
          'رقم الفاتورة: ${lastSale.invoiceNumber ?? lastSale.id}\n'
          'التاريخ: ${_formatDate(lastSale.saleDate)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // TODO: إعادة طباعة الإيصال
            },
            child: const Text('إعادة الطباعة'),
          ),
        ],
      ),
    );
  }

  // ⬇️ تم تعديل الدالة لتفتح شاشة المرتجع الجديدة
  Future<void> _openReturns(BuildContext context) async {
    final navigator = Navigator.of(context);
    navigator.pop(); // إغلاق القائمة السفلية
    
    if (!context.mounted) return;

    // فتح الشاشة المستقلة للمرتجع
    await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const SaleReturnFormPage(),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd HH:mm').format(date.toLocal());
  }

  static String _labelOf(ReceiptPaperSize size) {
    switch (size) {
      case ReceiptPaperSize.mm58:
        return '58 مم';
      case ReceiptPaperSize.mm80:
        return '80 مم';
      case ReceiptPaperSize.a4:
        return 'A4';
    }
  }
}

// ============================================================================
// Action tile
// ============================================================================

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color iconColor = enabled
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);
    final Color foreground = enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.65);

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 6,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!enabled)
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                child: Text(
                  'غير متاح',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            Icon(
              Icons.chevron_left,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.75,
      child: enabled
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: content,
            )
          : content,
    );
  }
}
