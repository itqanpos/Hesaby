// lib/features/suppliers/presentation/pages/supplier_statement_page.dart
//
// Thin adapter: feeds the generic AccountStatementPage with the
// supplier-specific pieces (data binding, flattening, print, record
// payment).
//
// Note: `Supplier` does not carry a cached `balance` column (unlike
// `Customer`), so `SupplierStatementAdapter.adapt` leaves
// `StatementView.storedBalance` null. As a result the reconciliation
// warning in the summary bar is inert for supplier statements.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show Printing;

import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/statements/account_statement_page.dart';
import '../../../../shared/widgets/statements/adapters/statement_adapter.dart';
import '../../../../shared/widgets/statements/models/statement_models.dart';
import '../../../pos/data/services/direct_print_service.dart';
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

  try {
    final Uint8List? logo = await _loadLogoBytes(ref);
    final Uint8List bytes = await PdfSupplierStatementBuilder.build(
      statement: statement,
      style: _readA4Style(ref),
      logoBytes: logo,
    );

    final String fileName =
        'supplier-statement-${statement.supplier.name}.pdf';

    final bool direct =
        ref.read(companySettingsProvider).valueOrNull?.printDirectEnabled ??
            false;

    if (direct) {
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

    await Printing.layoutPdf(
      name: fileName,
      onLayout: (PdfPageFormat _) async => bytes,
    );
  } on Object {
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
