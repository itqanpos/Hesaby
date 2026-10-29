// lib/features/cash/presentation/pages/shift_report_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart' show Printing;

import '../../../../core/utils/formatters.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/members_providers.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart' show ReceiptPaperSize;
import '../../../reports/data/services/pdf_report_builder.dart';
import '../../../reports/domain/entities/report_document.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../domain/entities/cash_entities.dart';
import '../providers/cash_providers.dart';

class ShiftReportPage extends ConsumerWidget {
  const ShiftReportPage({super.key, required this.shiftId});
  final String shiftId;

  Future<void> _printReport(
    BuildContext context,
    WidgetRef ref,
    Shift shift,
    List<CashTransaction> transactions,
    String cashierName,
    double expected,
    double actual,
    double diff,
  ) async {
    // 1. اختيار مقاس الطباعة
    final ReceiptPaperSize? selectedSize = await showDialog<ReceiptPaperSize>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('اختر مقاس الطباعة'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ReceiptPaperSize.a4),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Row(children: [Icon(Icons.description_outlined), SizedBox(width: 8), Text('A4 (تفصيلي)')])),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ReceiptPaperSize.mm80),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Row(children: [Icon(Icons.receipt_long_outlined), SizedBox(width: 8), Text('إيصال حراري 80 مم (ملخص)')])),
          ),
        ],
      ),
    );

    if (selectedSize == null || !context.mounted) return;

    final CompanySettings? settings = ref.read(companySettingsProvider).valueOrNull;
    final style = settings == null ? const PrintStyleSettings.defaults() : PrintStyleSettings.fromCompanySettings(settings);
    final contextState = ref.read(companyContextProvider);

    // 2. بناء التقرير
    final doc = ReportDocument(
      title: 'تقرير وردية',
      companyName: contextState.currentCompany?.name ?? '—',
      branchName: contextState.currentBranch?.name,
      generatedAt: DateTime.now(),
      periodLabel: 'وردية ${AppFormatters.dateTime(shift.openedAt)}',
      sections: [
        ReportSection(
          title: 'ملخص الوردية',
          kpis: [
            ReportKpi(label: 'الكاشير', value: cashierName),
            ReportKpi(label: 'الافتتاحي', value: AppFormatters.money(shift.openingBalance)),
            ReportKpi(label: 'المتوقع', value: AppFormatters.money(expected)),
            ReportKpi(label: 'الفعلي', value: AppFormatters.money(actual)),
            ReportKpi(label: 'الفرق', value: AppFormatters.money(diff), emphasized: true),
          ],
        ),
        ReportSection(
          title: 'تفاصيل الحركات (${transactions.length})',
          table: ReportTable(
            headers: const ['النوع', 'الحساب', 'وارد', 'صادر'],
            columnCount: 4,
            flex: const [2, 2, 1, 1],
            rows: [
              for (final tx in transactions)
                [
                  tx.categoryName ?? _sourceLabel(tx.sourceType),
                  tx.accountName,
                  tx.direction == CashDirection.inFlow ? AppFormatters.money(tx.amount) : '—',
                  tx.direction == CashDirection.outFlow ? AppFormatters.money(tx.amount) : '—',
                ]
            ],
          ),
        ),
      ],
    );

    // 3. الطباعة / المشاركة
    try {
      final bytes = await PdfReportBuilder.build(
        document: doc,
        style: style,
        size: selectedSize,
      );
      
      final String fileName = 'shift-${shift.id.substring(0, 8)}.pdf';
      
      // استخدام sharePdf لإخفاء حوار الطباعة الخاص بالنظام
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّرت طباعة التقرير.')));
    }
  }

  static String _sourceLabel(String sourceType) => switch (sourceType) {
        'sale' => 'بيع',
        'purchase' => 'مشتريات',
        'expense' => 'مصروف',
        'salary' => 'راتب',
        'advance' => 'سلفة',
        'manual' => 'حركة يدوية',
        _ => sourceType,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftAsync = ref.watch(shiftByIdProvider(shiftId));
    final txAsync = ref.watch(shiftTransactionsProvider(shiftId));
    final memberAsync = ref.watch(currentMemberProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('تقرير الوردية'),
      ),
      body: shiftAsync.when(
        loading: () => const AppLoader(),
        error: (e, _) => AppErrorView(
          title: 'تعذّر تحميل الوردية',
          message: 'حدث خطأ.',
          retryLabel: 'رجوع',
          onRetry: () => Navigator.pop(context),
        ),
        data: (shift) {
          final transactions = txAsync.valueOrNull ?? [];
          
          double totalIn = 0;
          double totalOut = 0;
          for (final tx in transactions) {
            if (tx.direction == CashDirection.inFlow) {
              totalIn += tx.amount;
            } else {
              totalOut += tx.amount;
            }
          }
          final expected = shift.openingBalance + totalIn - totalOut;
          final actual = shift.actualClosingBalance ?? 0;
          final diff = actual - expected;
          
          // محاولة جلب اسم الكاشير
          final cashierName = memberAsync.valueOrNull?.id == shift.cashierId 
              ? (memberAsync.valueOrNull?.displayName ?? 'موظف')
              : 'موظف';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(
                shift: shift,
                cashierName: cashierName,
                expected: expected,
                actual: actual,
                diff: diff,
                onPrint: () => _printReport(context, ref, shift, transactions, cashierName, expected, actual, diff),
              ),
              const SizedBox(height: 16),
              Text('تفاصيل الحركات (${transactions.length})', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (transactions.isEmpty)
                const Text('لا توجد حركات في هذه الوردية.')
              else
                for (final tx in transactions)
                  ListTile(
                    title: Text(tx.categoryName ?? _sourceLabel(tx.sourceType)),
                    subtitle: Text('${tx.accountName} · ${AppFormatters.time(tx.transactionDate)}'),
                    trailing: Text(
                      '${tx.direction == CashDirection.inFlow ? '+' : '-'}${AppFormatters.money(tx.amount)}',
                      style: TextStyle(
                        color: tx.direction == CashDirection.inFlow ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.shift,
    required this.cashierName,
    required this.expected,
    required this.actual,
    required this.diff,
    required this.onPrint,
  });

  final Shift shift;
  final String cashierName;
  final double expected;
  final double actual;
  final double diff;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('الوردية: $cashierName', style: theme.textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.print_outlined),
                  tooltip: 'طباعة التقرير',
                  onPressed: onPrint,
                ),
              ],
            ),
            Text('فُتحت: ${AppFormatters.dateTime(shift.openedAt)}', style: theme.textTheme.bodySmall),
            const Divider(),
            _row('الرصيد الافتتاحي', AppFormatters.money(shift.openingBalance)),
            _row('المتوقع', AppFormatters.money(expected)),
            _row('الفعلي', AppFormatters.money(actual)),
            _row('الفرق', AppFormatters.money(diff), isBold: true, color: diff < 0 ? Colors.red : Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : null, color: color)),
        ],
      ),
    );
  }
}
