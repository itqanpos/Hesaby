// lib/features/settings/presentation/widgets/print_actions_settings_section.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../pos/data/services/pos_preferences.dart';
import '../../../pos/domain/entities/receipt.dart';
import '../../../sales/presentation/services/sale_print_actions.dart';
import '../../../sales/domain/entities/sale_entities.dart'; // For Dummy Sale

class PrintActionsSettingsSection extends ConsumerWidget {
  const PrintActionsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<bool> autoPrintAsync = ref.watch(autoPrintProvider);
    final bool autoPrint = autoPrintAsync.valueOrNull ?? false;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1. مفتاح الطباعة التلقائية
        SwitchListTile(
          title: const Text('الطباعة التلقائية'),
          subtitle: const Text('طباعة الفاتورة تلقائياً فور إتمام عملية البيع في نقطة البيع.'),
          value: autoPrint,
          activeThumbColor: scheme.primary,
          onChanged: (bool value) {
            ref.read(autoPrintProvider.notifier).setAutoPrint(value);
          },
        ),
        const Divider(),
        
        // 2. زر الطباعة التجريبية
        ListTile(
          leading: Icon(Icons.print_outlined, color: scheme.primary),
          title: const Text('إجراء طباعة تجريبية'),
          subtitle: const Text('طباعة فاتورة وهمية للتأكد من أن الطابعة متصلة وتعمل بشكل صحيح.'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => _handleTestPrint(context, ref),
        ),
      ],
    );
  }

  Future<void> _handleTestPrint(BuildContext context, WidgetRef ref) async {
    // بناء فاتورة وهمية
    final dummyReceipt = Receipt(
      saleId: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
      invoiceNumber: 'TEST-001',
      dateTime: DateTime.now(),
      companyName: 'شركة تجريبية',
      branchName: 'الفرع الرئيسي',
      lines: [
        ReceiptLine(
          productName: 'منتج تجريبي للتأكد من جودة الطباعة',
          unitName: 'قطعة',
          quantity: 1,
          unitPrice: 100.0,
          lineTotal: 100.0,
        ),
      ],
      subtotal: 100.0,
      discount: 0.0,
      taxAmount: 0.0,
      total: 100.0,
      paidAmount: 100.0,
      footer: 'هذه فاتورة تجريبية. يرجى التخلص منها.',
    );

    // استدعاء محرك الطباعة
    await handleSalePrintFlow(
      context: context,
      ref: ref,
      sale: Sale(
        id: dummyReceipt.saleId,
        companyId: 'test',
        branchId: 'test',
        saleDate: dummyReceipt.dateTime,
        status: 'confirmed',
        subtotal: dummyReceipt.subtotal,
        discount: dummyReceipt.discount,
        taxAmount: dummyReceipt.taxAmount,
        total: dummyReceipt.total,
        paidAmount: dummyReceipt.paidAmount,
        paymentStatus: 'paid',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      items: [], // لا نحتاجها هنا لأننا مررنا الـ Receipt جاهزاً
      customerName: 'عميل تجريبي',
      productNames: {},
      unitNames: {},
      forceShare: false, // جرّب الطباعة المباشرة أولاً
    );
  }
}
