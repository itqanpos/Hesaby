// lib/features/suppliers/presentation/pages/supplier_statement_page.dart
//
// Thin adapter: feeds the generic AccountStatementPage with the
// supplier-specific pieces (data binding, flattening, print, record
// payment).
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
import '../../../purchases/presentation/dialogs/supplier_payment_dialog.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/company_settings.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../data/services/pdf_supplier_statement_builder.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/entities/supplier_statement.dart';
import '../../domain/repositories/supplier_statement_repository.dart';
import '../providers/supplier_statement_providers.dart';

class SupplierStatementPage extends ConsumerWidget {
  const SupplierStatementPage({
    super.key,
    required this.supplier,
  });

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AccountStatementPage<SupplierStatement>(
      config: StatementPageConfig<SupplierStatement>(
        title: 'كشف حساب مورد',
        avatarIcon: Icons.local_shipping_outlined,
        partyKind: StatementPartyKind.supplier,
        watch: (WidgetRef ref, DateTime? from, DateTime? to) {
          return ref.watch(
            supplierStatementProvider(
              SupplierStatementArgs(
                supplierId: supplier.id,
                fromDate: from,
                toDate: to,
              ),
            ),
          );
        },
        adapt: (SupplierStatement raw) =>
            const SupplierStatementAdapter().adapt(raw),
        refresh: (WidgetRef ref, DateTime? from, DateTime? to) async {
          final SupplierStatementArgs args = SupplierStatementArgs(
            supplierId: supplier.id,
            fromDate: from,
            toDate: to,
          );
          ref.invalidate(supplierStatementProvider(args));
          await ref.read(supplierStatementProvider(args).future);
        },
        errorMessage: _errorMessage,
        print: _print,
        extraAction: StatementExtraAction(
          icon: Icons.payments_outlined,
          tooltip: 'تسجيل دفعة',
          onPressed: (BuildContext ctx, WidgetRef r, StatementView? _) async {
            final bool? saved = await showSupplierPaymentDialog(
              context: ctx,
              supplierId: supplier.id,
              supplierName: supplier.name,
            );
            return saved == true;
          },
        ),
      ),
    );
  }
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
  SupplierStatement statement,
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
    final Uint8List bytes = await PdfSupplierStatementBuilder.build(
      statement: statement,
      style: _readA4Style(ref),
      logoBytes: logo,
      size: selectedSize,
      companyName: companyCtx.currentCompany?.name,
      branchName: companyCtx.currentBranch?.name,
    );

    final String fileName =
        'supplier-statement-${statement.supplier.name}-${DateTime.now().millisecondsSinceEpoch}.pdf';

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
    AppLogger.warning('Supplier statement print failed: $e');
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
  if (error is SupplierStatementException) {
    return _failureMessage(error.type);
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}

String _failureMessage(SupplierStatementFailureType type) {
  switch (type) {
    case SupplierStatementFailureType.network:
      return 'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.';
    case SupplierStatementFailureType.unauthorized:
      return 'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مجددًا.';
    case SupplierStatementFailureType.notFound:
      return 'المورد المطلوب غير موجود.';
    case SupplierStatementFailureType.invalidResponse:
      return 'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.';
    case SupplierStatementFailureType.unknown:
      return 'تعذّر إتمام العملية. يرجى المحاولة مرة أخرى.';
  }
}
