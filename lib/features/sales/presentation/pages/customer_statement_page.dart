// lib/features/sales/presentation/pages/customer_statement_page.dart
//
// Thin adapter: feeds the generic AccountStatementPage with the
// customer-specific pieces (data binding, flattening, print, adjust).
//
// **Updates:**
// * Removed `Printing.layoutPdf` in favour of `Printing.sharePdf`.
// * Added paper size selection (A4 / Thermal 80mm).
// * Company info now comes from `companyContextProvider` (not
//   `CompanySettings`, which does not carry name/address).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart' show Printing;

import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/statements/account_statement_page.dart';
import '../../../../shared/widgets/statements/adapters/statement_adapter.dart';
import '../../../../shared/widgets/statements/models/statement_models.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../pos/data/services/direct_print_service.dart';
import '../../../pos/data/services/pdf_receipt_builder.dart'
    show ReceiptPaperSize;
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/pdf_statement_builder.dart';
import '../../domain/entities/customer_statement.dart';
import '../../domain/entities/sale_entities.dart';
import '../../domain/repositories/sales_repository.dart';
import '../dialogs/customer_adjustment_dialog.dart';
import '../providers/sales_providers.dart';

class CustomerStatementPage extends ConsumerWidget {
  const CustomerStatementPage({
    super.key,
    required this.customer,
  });

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AccountStatementPage<CustomerStatement>(
      config: StatementPageConfig<CustomerStatement>(
        title: 'كشف حساب',
        avatarIcon: Icons.person_outline,
        partyKind: StatementPartyKind.customer,
        watch: (WidgetRef ref, DateTime? from, DateTime? to) {
          return ref.watch(
            customerStatementProvider(
              CustomerStatementArgs(
                customerId: customer.id,
                fromDate: from,
                toDate: to,
              ),
            ),
          );
        },
        adapt: (CustomerStatement raw) =>
            const CustomerStatementAdapter().adapt(raw),
        refresh: (WidgetRef ref, DateTime? from, DateTime? to) async {
          final CustomerStatementArgs args = CustomerStatementArgs(
            customerId: customer.id,
            fromDate: from,
            toDate: to,
          );
          ref.invalidate(customerStatementProvider(args));
          await ref.read(customerStatementProvider(args).future);
        },
        errorMessage: _errorMessage,
        print: _print,
        extraAction: StatementExtraAction(
          icon: Icons.tune,
          tooltip: 'تعديل الرصيد',
          onPressed: (BuildContext ctx, WidgetRef r, StatementView? view) {
            return _openAdjustment(
              context: ctx,
              ref: r,
              customer: customer,
              view: view,
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// Extra action — adjust balance
// ============================================================================

Future<bool> _openAdjustment({
  required BuildContext context,
  required WidgetRef ref,
  required Customer customer,
  required StatementView? view,
}) async {
  final double currentBalance = view?.storedBalance ?? customer.balance;

  final Customer? updated = await showCustomerAdjustmentDialog(
    context: context,
    customerId: customer.id,
    customerName: customer.name,
    currentBalance: currentBalance,
  );

  if (updated == null || !context.mounted) return false;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('تم تسجيل التعديل بنجاح.')),
    );
  return true;
}

// ============================================================================
// Print
// ============================================================================

PrintStyleSettings _readA4Style(WidgetRef ref) {
  final CompanySettings? s =
      ref.read(companySettingsProvider).valueOrNull;
  if (s == null) return const PrintStyleSettings.defaults();
  return PrintStyleSettings(
    fontScale: s.printFontScaleA4,
    fontWeight: s.printFontWeight,
  );
}

Future<Uint8List?> _loadLogoBytes(WidgetRef ref) async {
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

Future<void> _print(
  BuildContext context,
  WidgetRef ref,
  CustomerStatement statement,
) async {
  if (statement.isEmpty) return;

  // 1. اختيار مقاس الطباعة
  final ReceiptPaperSize? selectedSize = await showDialog<ReceiptPaperSize>(
    context: context,
    builder: (BuildContext ctx) {
      return SimpleDialog(
        title: const Text('اختر مقاس الطباعة'),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ReceiptPaperSize.a4),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.description_outlined),
                  SizedBox(width: 8),
                  Text('A4 (تفصيلي)'),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ReceiptPaperSize.mm80),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.receipt_long_outlined),
                  SizedBox(width: 8),
                  Text('إيصال حراري 80 مم (ملخص)'),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  if (selectedSize == null || !context.mounted) return;

  try {
    final CompanySettings? settings =
        ref.read(companySettingsProvider).valueOrNull;
    final CompanyContextState companyCtx =
        ref.read(companyContextProvider);
    final Uint8List? logo = await _loadLogoBytes(ref);

    // 2. بناء الـ PDF
    final Uint8List bytes = await PdfStatementBuilder.build(
      statement: statement,
      style: _readA4Style(ref),
      logoBytes: logo,
      size: selectedSize,
      // companyName / branchName from companyContextProvider.
      // address / phone / taxNumber / commercialRegister: null for now
      // (they live on Company/Branch entities — not on CompanySettings).
      companyName: companyCtx.currentCompany?.name,
      branchName: companyCtx.currentBranch?.name,
    );

    final String fileName =
        'statement-${statement.customer.name}-${DateTime.now().millisecondsSinceEpoch}.pdf';

    // 3. محاولة الطباعة المباشرة (إذا كانت مفعلة ومقاس حراري)
    final bool direct = settings?.printDirectEnabled ?? false;

    if (direct && selectedSize != ReceiptPaperSize.a4) {
      final bool ok = await DirectPrintService.tryPdfBytes(
        bytes: bytes,
        name: fileName,
      );
      if (ok) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('تم إرسال الكشف للطابعة.')),
          );
        return;
      }
    }

    // 4. شيت المشاركة (بدلاً من layoutPdf)
    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName,
    );
  } on Object catch (e) {
    AppLogger.warning('Statement print failed: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('تعذّرت الطباعة. حاول مرة أخرى.')),
      );
  }
}

// ============================================================================
// Localization
// ============================================================================

String _errorMessage(Object error) {
  if (error is CustomerException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(CustomerFailureType type) {
  switch (type) {
    case CustomerFailureType.network:
      return 'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.';
    case CustomerFailureType.unauthorized:
      return 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مجددًا.';
    case CustomerFailureType.notFound:
      return 'العميل المطلوب غير موجود أو تم حذفه.';
    case CustomerFailureType.nameConflict:
      return 'يوجد عميل آخر بنفس الاسم.';
    case CustomerFailureType.codeConflict:
      return 'يوجد عميل آخر بنفس الكود.';
    case CustomerFailureType.phoneConflict:
      return 'يوجد عميل آخر بنفس رقم الهاتف.';
    case CustomerFailureType.inUse:
      return 'العميل مرتبط بفواتير.';
    case CustomerFailureType.invalidAmount:
      return 'المبلغ غير صالح.';
    case CustomerFailureType.insufficientBalance:
      return 'الرصيد غير كافٍ لإتمام العملية.';
    case CustomerFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.';
    case CustomerFailureType.unknown:
      return 'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.';
  }
}
