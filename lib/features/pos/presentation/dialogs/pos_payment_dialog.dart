// lib/features/pos/presentation/dialogs/pos_payment_dialog.dart

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/invalidation/data_invalidation.dart';
import '../../../../core/network/network_status_provider.dart';
import '../../../../core/network/offline_writer.dart';
import '../../../../core/printing/app_print_engine.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../cash/domain/entities/cash_entities.dart';
import '../../../cash/presentation/providers/cash_providers.dart';
import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../../companies/presentation/providers/company_status_provider.dart';
import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/domain/repositories/sales_repository.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../../settings/presentation/providers/user_profile_providers.dart';
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/receipt_printer.dart';
import '../../domain/entities/pos_cart.dart';
import '../../domain/entities/pos_cart_line.dart';
import '../../domain/entities/receipt.dart';
import '../providers/printer_providers.dart';
import '../state/pos_providers.dart';
import 'pos_print_preview_dialog.dart';

abstract final class PosPaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String instapay = 'instapay';
  static const String bankTransfer = 'bank_transfer';
  static const String other = 'other';

  static const List<String> all = <String>[
    cash,
    card,
    instapay,
    bankTransfer,
    other,
  ];

  static String label(String method) => switch (method) {
        cash => 'نقدي',
        card => 'بطاقة',
        instapay => 'InstaPay',
        bankTransfer => 'تحويل بنكي',
        _ => 'أخرى',
      };

  static IconData icon(String method) => switch (method) {
        cash => Icons.payments_outlined,
        card => Icons.credit_card,
        instapay => Icons.phone_iphone,
        bankTransfer => Icons.account_balance_outlined,
        _ => Icons.more_horiz,
      };
}

/// Opens the POS payment dialog.
Future<bool?> showPosPaymentDialog({required BuildContext context}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => const _PosPaymentSheet(),
  );
}

// ============================================================================
// Payment entry
// ============================================================================

class _PaymentEntry {
  _PaymentEntry({
    required this.method,
    required this.amount,
  }) : controller = TextEditingController(
          text: _formatAmount(amount),
        );

  String method;
  double amount;
  final TextEditingController controller;

  void dispose() => controller.dispose();

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }
}

// ============================================================================
// Payment sheet
// ============================================================================

class _PosPaymentSheet extends ConsumerStatefulWidget {
  const _PosPaymentSheet();

  @override
  ConsumerState<_PosPaymentSheet> createState() => _PosPaymentSheetState();
}

class _PosPaymentSheetState extends ConsumerState<_PosPaymentSheet> {
  late final PosCart _cart;
  late final PosTotals _totals;

  late final List<_PaymentEntry> _payments;

  bool _isSubmitting = false;
  SalesFailureType? _serverFailure;

  @override
  void initState() {
    super.initState();
    _cart = ref.read(posCartProvider);
    _totals = ref.read(posTotalsProvider);

    // ✅ الإصلاح 1: لا نضع قيمة سالبة في الحقل
    _payments = <_PaymentEntry>[
      _PaymentEntry(
        method: PosPaymentMethod.cash,
        amount: _settlementTotal > 0 ? _settlementTotal : 0,
      ),
    ];
  }

  @override
  void dispose() {
    for (final _PaymentEntry p in _payments) {
      p.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Derived
  // ---------------------------------------------------------------------------

  double get _saleTotal => _totals.total;
  double get _settlementTotal => _cart.customerBalance + _saleTotal;

  double get _totalPaid =>
      _payments.fold<double>(0, (double s, _PaymentEntry p) => s + p.amount);

  double get _remaining {
    final double r = _settlementTotal - _totalPaid;
    return r > 0 ? r : 0;
  }

  // ✅ الإصلاح 2: الأساس هو max(settlementTotal, 0) — لا "زيادة" وهمية
  double get _overpay {
    final double base = _settlementTotal > 0 ? _settlementTotal : 0;
    final double o = _totalPaid - base;
    return o > 0 ? o : 0;
  }

  bool get _isCredit => _payments.isEmpty;

  /// لا يوجد مبلغ مطلوب (الرصيد الدائن يغطي)
  bool get _hasNoDue => _settlementTotal <= 0.001;

  // ---------------------------------------------------------------------------
  // Payment list mutations
  // ---------------------------------------------------------------------------

  void _addPayment() {
    setState(() {
      final double amount = _remaining > 0 ? _remaining : 0;
      _payments.add(_PaymentEntry(
        method: PosPaymentMethod.cash,
        amount: amount,
      ));
    });
  }

  void _removePayment(int index) {
    setState(() {
      _payments[index].dispose();
      _payments.removeAt(index);
      if (_payments.isEmpty) {
        _payments.add(_PaymentEntry(
          method: PosPaymentMethod.cash,
          amount: 0,
        ));
      }
    });
  }

  void _updateMethod(int index, String method) {
    setState(() => _payments[index].method = method);
  }

  void _updateAmount(int index, String raw) {
    final double parsed = double.tryParse(raw.trim()) ?? 0;
    setState(() => _payments[index].amount = parsed < 0 ? 0 : parsed);
  }

  void _selectCredit() {
    setState(() {
      for (final _PaymentEntry p in _payments) {
        p.dispose();
      }
      _payments.clear();
    });
  }

  void _selectPayNow() {
    setState(() {
      if (_payments.isEmpty) {
        // ✅ الإصلاح 4: clamp القيمة الافتراضية
        _payments.add(_PaymentEntry(
          method: PosPaymentMethod.cash,
          amount: _settlementTotal > 0 ? _settlementTotal : 0,
        ));
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _validationError() {
    if (_cart.isEmpty) return 'السلة فارغة. أضف منتجاً قبل الدفع.';
    if (_cart.discount > _cart.subtotal) {
      return 'الخصم أكبر من المجموع الفرعي للفاتورة.';
    }
    if (_saleTotal <= 0) {
      return 'إجمالي الفاتورة يجب أن يكون أكبر من صفر.';
    }

    if (_isCredit) {
      if (!_cart.hasCustomer) {
        return 'البيع الآجل يتطلب اختيار عميل مسجل.';
      }
      return null;
    }

    if (_payments.isEmpty) {
      return 'أضف طريقة دفع واحدة على الأقل.';
    }

    // ✅ الإصلاح 3: لا نطلب دفعًا إن كان الرصيد الدائن يغطي
    if (_settlementTotal > 0 && _totalPaid <= 0) {
      return 'أدخل مبلغاً أكبر من صفر في إحدى الدفعات.';
    }

    if (_totalPaid < _saleTotal && !_cart.hasCustomer) {
      return 'الدفع الجزئي يتطلب اختيار عميل مسجل.';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!ref.read(companyCanWriteProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن إتمام البيع. الحساب موقوف أو اشتراكه منتهي.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_validationError() != null) return;

    final CompanyContextState contextState = ref.read(companyContextProvider);
    final String? branchId = contextState.currentBranch?.id;
    if (branchId == null) {
      setState(() => _serverFailure = SalesFailureType.branchNotFound);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serverFailure = null;
    });

    final bool isOnline = ref.read(isOnlineProvider);
    if (!isOnline) {
      await _submitOffline(contextState: contextState, branchId: branchId);
      return;
    }

    await _submitOnline(contextState: contextState, branchId: branchId);
  }

  Future<void> _submitOnline({
    required CompanyContextState contextState,
    required String branchId,
  }) async {
    final SalesNotifier notifier = ref.read(salesProvider.notifier);
    Sale? createdSale;

    try {
      final double saleTotal = _saleTotal;
      final double totalPaid = _isCredit ? 0 : _totalPaid;
      final double appliedToSale = totalPaid < saleTotal ? totalPaid : saleTotal;
      final double appliedToBalance =
          totalPaid > saleTotal ? (totalPaid - saleTotal) : 0;

      final Sale sale = await notifier.createSale(
        branchId: branchId,
        customerId: _cart.customerId,
        saleDate: DateTime.now(),
        items: <SaleItemDraft>[
          for (final PosCartLine line in _cart.lines)
            SaleItemDraft(
              productId: line.productId,
              unitId: line.unitId,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
            ),
        ],
        discount: _cart.discount,
        taxAmount: _totals.taxAmount,
        paidAmount: appliedToSale,
      );
      createdSale = sale;

      final Sale confirmed = await notifier.confirmSale(sale.id);

      if (appliedToSale > 0 && _payments.isNotEmpty) {
        final List<SalePaymentDraft> salePayments = <SalePaymentDraft>[];
        double remaining = appliedToSale;
        for (final _PaymentEntry entry in _payments) {
          if (remaining <= 0) break;
          final double amt =
              entry.amount < remaining ? entry.amount : remaining;
          if (amt > 0) {
            salePayments.add(
              SalePaymentDraft(amount: amt, method: entry.method),
            );
            remaining -= amt;
          }
        }
        if (salePayments.isNotEmpty) {
          await ref.read(cashRepositoryProvider).recordSalePayments(
                companyId: contextState.currentCompany?.id ?? '',
                saleId: confirmed.id,
                payments: salePayments,
              );
        }
      }

      if (appliedToBalance > 0 && _cart.customerId != null) {
        final String method =
            _payments.isNotEmpty ? _payments.last.method : 'cash';
        await ref.read(customersProvider.notifier).recordPayment(
              customerId: _cart.customerId!,
              amount: appliedToBalance,
              method: method,
              notes: 'دفعة زيادة من فاتورة '
                  '${confirmed.invoiceNumber ?? confirmed.id}',
            );
      }

      DataInvalidation.afterSale(ref);

      if (!mounted) return;

      final Receipt receipt = _buildReceipt(
        saleId: confirmed.id,
        invoiceNumber: confirmed.invoiceNumber,
        saleDate: confirmed.saleDate,
        contextState: contextState,
      );

      ref.read(posCartProvider.notifier).reset();
      await _afterSubmit(receipt);
    } on SaleException catch (error) {
      if (error.type == SalesFailureType.network && createdSale == null) {
        if (!mounted) return;
        await _submitOffline(contextState: contextState, branchId: branchId);
        return;
      }
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _serverFailure =
            createdSale == null ? error.type : SalesFailureType.unknown;
      });
    } on Object {
      if (!mounted) return;
      if (createdSale != null) {
        setState(() {
          _isSubmitting = false;
          _serverFailure = SalesFailureType.unknown;
        });
        return;
      }
      await _submitOffline(contextState: contextState, branchId: branchId);
    }
  }

  Future<void> _submitOffline({
    required CompanyContextState contextState,
    required String branchId,
  }) async {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (final PosCartLine line in _cart.lines)
        <String, Object?>{
          'product_id': line.productId,
          'unit_id': line.unitId,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'notes': null,
        },
    ];

    final double saleTotal = _saleTotal;
    final double totalPaid = _isCredit ? 0 : _totalPaid;
    final double appliedToSale = totalPaid < saleTotal ? totalPaid : saleTotal;
    final double appliedToBalance =
        totalPaid > saleTotal ? (totalPaid - saleTotal) : 0;

    final String? paymentMethod = _isCredit
        ? null
        : (_payments.isNotEmpty ? _payments.first.method : 'cash');

    final String? saleUuid = await OfflineWriter.enqueueSale(
      ref: ref,
      branchId: branchId,
      customerId: _cart.customerId,
      saleDate: DateTime.now(),
      items: items,
      discount: _cart.discount,
      taxAmount: _totals.taxAmount,
      paidAmount: appliedToSale,
      paymentMethod: paymentMethod,
      notes: null,
    );

    if (saleUuid == null) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _serverFailure = SalesFailureType.unknown;
      });
      return;
    }

    if (appliedToBalance > 0 && _cart.customerId != null) {
      await OfflineWriter.enqueueCustomerPayment(
        ref: ref,
        customerId: _cart.customerId!,
        amount: appliedToBalance,
        method: paymentMethod ?? 'cash',
        notes: 'دفعة زيادة من فاتورة أوفلاين',
      );
    }

    if (!mounted) return;

    final Receipt receipt = _buildReceipt(
      saleId: saleUuid,
      invoiceNumber: null,
      saleDate: DateTime.now(),
      contextState: contextState,
    );

    ref.read(posCartProvider.notifier).reset();
    await _afterSubmit(receipt, isOffline: true);
  }

  Future<void> _afterSubmit(Receipt receipt, {bool isOffline = false}) async {
    final bool directPrint =
        ref.read(companySettingsProvider).valueOrNull?.printDirectEnabled ??
            false;
    final bool isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS;
    final bool hasSavedPrinter =
        ref.read(savedPrinterProvider).valueOrNull != null;

    if (directPrint && isDesktop && hasSavedPrinter) {
      try {
        final engine = ref.read(appPrintEngineProvider);
        final logo = await _loadLogoBytes();
        final style = _readStyle();
        final bool ok = await engine.printThermal(
          receipt: receipt,
          paperWidthDots: _thermalWidthDots(),
          logoBytes: logo,
          style: style,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? (isOffline
                      ? 'تم الحفظ محلياً والطباعة المباشرة.'
                      : 'تم إتمام البيع والطباعة المباشرة.')
                  : (isOffline
                      ? 'تم الحفظ محلياً، لكن تعذّرت الطباعة.'
                      : 'تم إتمام البيع، لكن تعذّرت الطباعة.'),
            ),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم الحفظ، لكن حدث خطأ أثناء الطباعة.'),
          ),
        );
      }
    } else {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => _PosReceiptDialog(
          receipt: receipt,
          isOffline: isOffline,
        ),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<Uint8List?> _loadLogoBytes() async {
    final settings = ref.read(companySettingsProvider).valueOrNull;
    if (settings == null || settings.companyId.isEmpty) return null;
    try {
      return await const CompanyLogoLoader().load(
        companyId: settings.companyId,
        logoUrl: settings.logoUrl,
      );
    } catch (_) {
      return null;
    }
  }

  PrintStyleSettings _readStyle() {
    final settings = ref.read(companySettingsProvider).valueOrNull;
    if (settings == null) return const PrintStyleSettings.defaults();
    return PrintStyleSettings.fromCompanySettings(settings);
  }

  int _thermalWidthDots() {
    final size = ref.read(posPaperSizeProvider).valueOrNull ??
        PosPreferences.defaultPaperSize;
    return size == ReceiptPaperSize.mm58 ? 384 : 576;
  }

  Receipt _buildReceipt({
    required String saleId,
    required String? invoiceNumber,
    required DateTime saleDate,
    required CompanyContextState contextState,
  }) {
    final cashierName = ref.read(userProfileProvider).valueOrNull?.fullName;

    String? customerAddress;
    String? customerPhone;
    if (_cart.customerId != null) {
      final AsyncValue<List<Customer>> customersAsync =
          ref.read(customersProvider);
      final List<Customer>? customers = customersAsync.valueOrNull;
      if (customers != null) {
        final Customer? customer = customers
            .cast<Customer?>()
            .firstWhere(
              (Customer? c) => c?.id == _cart.customerId,
              orElse: () => null,
            );
        if (customer != null) {
          customerAddress = customer.address;
          customerPhone = customer.phone;
        }
      }
    }

    final double totalPaid = _isCredit ? 0 : _totalPaid;
    final double newBalance = (_cart.hasCustomer)
        ? _cart.customerBalance + _saleTotal - totalPaid
        : 0;

    return Receipt(
      saleId: saleId,
      invoiceNumber: invoiceNumber,
      dateTime: saleDate,
      companyName: contextState.currentCompany?.name ?? '—',
      branchName: contextState.currentBranch?.name ?? '—',
      companyAddress: contextState.currentCompany?.address,
      companyPhone: contextState.currentCompany?.phone,
      companyTaxNumber: contextState.currentCompany?.taxNumber,
      companyCommercialRegister:
          contextState.currentCompany?.commercialRegister,
      showTaxNumberOnPrint: ref.read(showTaxNumberOnPrintProvider),
      showCommercialRegisterOnPrint:
          ref.read(showCommercialRegisterOnPrintProvider),
      showCurrencySymbol: ref.read(showCurrencySymbolProvider),
      lines: <ReceiptLine>[
        for (final PosCartLine line in _cart.lines)
          ReceiptLine(
            productName: line.productName,
            unitName: line.unitName,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            lineTotal: line.lineTotal,
          ),
      ],
      subtotal: _cart.subtotal,
      discount: _cart.discount,
      taxAmount: _totals.taxAmount,
      total: _saleTotal,
      paidAmount: totalPaid,
      payments: _isCredit
          ? const <ReceiptPayment>[]
          : <ReceiptPayment>[
              for (final _PaymentEntry entry in _payments)
                if (entry.amount > 0)
                  ReceiptPayment(
                    method: entry.method,
                    amount: entry.amount,
                  ),
            ],
      customerName: _cart.customerName,
      customerAddress: customerAddress,
      customerPhone: customerPhone,
      cashierName: cashierName,
      previousBalance: _cart.hasCustomer ? _cart.customerBalance : null,
      newBalance: _cart.hasCustomer ? newBalance : null,
      footer: ref.read(receiptFooterProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final String? validationError = _validationError();
    final String? failureMessage = _serverFailure != null
        ? _failureMessageFor(_serverFailure!)
        : null;
    final String? displayError = failureMessage ?? validationError;
    final bool canSubmit = !_isSubmitting && validationError == null;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Text('الدفع', style: theme.textTheme.titleLarge),
                      const Spacer(),
                      IconButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  _CustomerRow(customerName: _cart.customerName),
                  const SizedBox(height: 12),
                  _TotalsCard(
                    saleTotal: _saleTotal,
                    customerBalance: _cart.customerBalance,
                    hasCustomer: _cart.hasCustomer,
                  ),
                  const SizedBox(height: 16),

                  SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('دفع'),
                        icon: Icon(Icons.payments_outlined, size: 16),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('آجل'),
                        icon: Icon(Icons.schedule, size: 16),
                      ),
                    ],
                    selected: <bool>{_isCredit},
                    onSelectionChanged: _isSubmitting
                        ? null
                        : (Set<bool> s) {
                            if (s.first) {
                              _selectCredit();
                            } else {
                              _selectPayNow();
                            }
                          },
                  ),

                  const SizedBox(height: 16),

                  if (!_isCredit) ...<Widget>[
                    Text('طرق الدفع',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _payments.length; i++) ...<Widget>[
                      _PaymentEntryCard(
                        entry: _payments[i],
                        index: i,
                        canRemove: _payments.length > 1,
                        enabled: !_isSubmitting,
                        onMethodChanged: (String m) => _updateMethod(i, m),
                        onAmountChanged: (String v) => _updateAmount(i, v),
                        onRemove: () => _removePayment(i),
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextButton.icon(
                      onPressed: _isSubmitting ? null : _addPayment,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('إضافة طريقة دفع'),
                    ),
                    const SizedBox(height: 8),
                    _RemainingIndicator(
                      remaining: _remaining,
                      overpay: _overpay,
                      totalPaid: _totalPaid,
                      hasNoDue: _hasNoDue,
                    ),
                  ] else ...<Widget>[
                    _InfoBanner(
                      icon: Icons.info_outline,
                      message: 'سيتم إضافة كامل قيمة الفاتورة إلى رصيد العميل.',
                    ),
                  ],

                  if (displayError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: displayError),
                  ],

                  const SizedBox(height: 20),
                  AppButton(
                    label: 'إتمام البيع',
                    icon: Icons.check_circle_outline,
                    expanded: true,
                    size: AppButtonSize.large,
                    isLoading: _isSubmitting,
                    onPressed: canSubmit ? _submit : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Payment entry card
// ============================================================================

class _PaymentEntryCard extends StatelessWidget {
  const _PaymentEntryCard({
    required this.entry,
    required this.index,
    required this.canRemove,
    required this.enabled,
    required this.onMethodChanged,
    required this.onAmountChanged,
    required this.onRemove,
  });

  final _PaymentEntry entry;
  final int index;
  final bool canRemove;
  final bool enabled;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(
          children: <Widget>[
            PopupMenuButton<String>(
              enabled: enabled,
              tooltip: 'طريقة الدفع',
              onSelected: onMethodChanged,
              itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
                for (final String m in PosPaymentMethod.all)
                  PopupMenuItem<String>(
                    value: m,
                    child: Row(
                      children: <Widget>[
                        Icon(PosPaymentMethod.icon(m), size: 18),
                        const SizedBox(width: 8),
                        Text(PosPaymentMethod.label(m)),
                      ],
                    ),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      PosPaymentMethod.icon(entry.method),
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      PosPaymentMethod.label(entry.method),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: scheme.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: entry.controller,
                enabled: enabled,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                decoration: const InputDecoration(
                  hintText: '0',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  suffixText: 'ج.م',
                  border: OutlineInputBorder(),
                ),
                onChanged: onAmountChanged,
              ),
            ),
            if (canRemove)
              IconButton(
                tooltip: 'حذف',
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: enabled ? onRemove : null,
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Remaining indicator (✅ محدَّث — حالة "الرصيد يغطي")
// ============================================================================

class _RemainingIndicator extends StatelessWidget {
  const _RemainingIndicator({
    required this.remaining,
    required this.overpay,
    required this.totalPaid,
    required this.hasNoDue,
  });

  final double remaining;
  final double overpay;
  final double totalPaid;
  final bool hasNoDue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final bool fullyPaid = remaining <= 0.01 && overpay <= 0.01;
    final bool overpaid = overpay > 0.01;

    final Color color = fullyPaid
        ? const Color(0xFF2E7D32)
        : overpaid
            ? const Color(0xFF0F7B6C)
            : scheme.error;

    final IconData icon = fullyPaid
        ? Icons.check_circle
        : overpaid
            ? Icons.trending_up
            : Icons.pending_outlined;

    // ✅ رسالة خاصة عندما الرصيد الدائن يغطي الفاتورة
    final String label;
    if (hasNoDue && !overpaid) {
      label = 'الرصيد السابق يغطي الفاتورة — لا مبلغ مطلوب';
    } else if (fullyPaid) {
      label = 'المدفوع مطابق للمطلوب';
    } else if (overpaid) {
      label = 'زيادة: ${AppFormatters.money(overpay)}';
    } else {
      label = 'المتبقي: ${AppFormatters.money(remaining)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            AppFormatters.money(totalPaid),
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Info banner
// ============================================================================

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(icon, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customerName});
  final String? customerName;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool hasCustomer = customerName != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              hasCustomer ? Icons.person : Icons.person_outline,
              color: scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasCustomer ? customerName! : 'عميل نقدي',
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.saleTotal,
    required this.customerBalance,
    required this.hasCustomer,
  });

  final double saleTotal;
  final double customerBalance;
  final bool hasCustomer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool showBalance = hasCustomer && customerBalance != 0;
    final double total =
        showBalance ? customerBalance + saleTotal : saleTotal;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: showBalance
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: showBalance
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _row(context, 'الرصيد السابق',
                      AppFormatters.money(customerBalance.abs()),
                      color: customerBalance > 0
                          ? scheme.error
                          : scheme.primary),
                  const SizedBox(height: 6),
                  _row(context, 'قيمة الفاتورة',
                      AppFormatters.money(saleTotal)),
                  const Divider(height: 16),
                  _row(context, 'الإجمالي المطلوب',
                      AppFormatters.money(total),
                      emphasized: true,
                      color: scheme.primary),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'الإجمالي المطلوب',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppFormatters.money(total),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool emphasized = false,
    Color? color,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyMedium,
          ),
        ),
        Text(
          value,
          style: (emphasized
                  ? theme.textTheme.headlineSmall
                  : theme.textTheme.bodyLarge)
              ?.copyWith(
            color: color ?? scheme.onSurface,
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline,
                color: scheme.onErrorContainer, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Receipt Dialog
// ============================================================================

class _PosReceiptDialog extends ConsumerStatefulWidget {
  const _PosReceiptDialog({
    required this.receipt,
    this.isOffline = false,
  });

  final Receipt receipt;
  final bool isOffline;

  @override
  ConsumerState<_PosReceiptDialog> createState() => _PosReceiptDialogState();
}

class _PosReceiptDialogState extends ConsumerState<_PosReceiptDialog> {
  static const ReceiptPrinter _pdfPrinter = ReceiptPrinterImpl();

  bool _isSharing = false;
  bool _isPrinting = false;

  Future<void> _handlePrint() async {
    if (!mounted) return;
    setState(() => _isPrinting = true);
    try {
      await showPosPrintPreviewDialog(
        context: context,
        receipt: widget.receipt,
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _handleShare() async {
    setState(() => _isSharing = true);
    try {
      final settings = ref.read(companySettingsProvider).valueOrNull;
      final style = settings == null
          ? const PrintStyleSettings.defaults()
          : PrintStyleSettings.fromCompanySettings(settings);
      final size = ref.read(posPaperSizeProvider).valueOrNull ??
          PosPreferences.defaultPaperSize;

      final logo = await _loadLogoBytes();

      final bool ok = await _pdfPrinter.shareReceipt(
        receipt: widget.receipt,
        size: size,
        style: style,
        logoBytes: logo,
      );

      if (!mounted) return;
      setState(() => _isSharing = false);

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّرت مشاركة الإيصال.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSharing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّرت مشاركة الإيصال.')),
      );
    }
  }

  Future<Uint8List?> _loadLogoBytes() async {
    final settings = ref.read(companySettingsProvider).valueOrNull;
    if (settings == null || settings.companyId.isEmpty) return null;
    try {
      return await const CompanyLogoLoader().load(
        companyId: settings.companyId,
        logoUrl: settings.logoUrl,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool busy = _isSharing || _isPrinting;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: widget.isOffline
                        ? scheme.tertiaryContainer
                        : scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isOffline
                        ? Icons.cloud_done_outlined
                        : Icons.check_circle,
                    size: 52,
                    color: widget.isOffline
                        ? scheme.onTertiaryContainer
                        : scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text(
                widget.isOffline
                    ? 'تم الحفظ محلياً'
                    : 'تم البيع بنجاح',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.isOffline) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'سيُرسل تلقائياً عند عودة الاتصال',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : _handlePrint,
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print_outlined),
                  label: const Text('طباعة الإيصال'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 58),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _handleShare,
                      icon: _isSharing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.ios_share, size: 18),
                      label: const Text('مشاركة'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        textStyle: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('فاتورة جديدة'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        textStyle: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Localization
// ============================================================================

String _failureMessageFor(SalesFailureType type) => switch (type) {
      SalesFailureType.network =>
        'تعذّر الاتصال بالخادم. يرجى التحقق من اتصالك بالإنترنت.',
      SalesFailureType.unauthorized =>
        'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مجددًا.',
      SalesFailureType.notFound => 'الفاتورة غير موجودة.',
      SalesFailureType.invalidStatusTransition =>
        'لا يمكن إتمام العملية في الحالة الحالية.',
      SalesFailureType.emptySale => 'لا يمكن إتمام بيع بدون بنود.',
      SalesFailureType.invoiceNumberConflict =>
        'رقم الفاتورة مستخدم بالفعل.',
      SalesFailureType.customerNotFound =>
        'البيع الآجل يتطلب اختيار عميل مسجل.',
      SalesFailureType.branchNotFound =>
        'الفرع غير متاح. يرجى إعادة اختياره.',
      SalesFailureType.productNotFound =>
        'أحد المنتجات غير متاح. يرجى إزالته وإعادة المحاولة.',
      SalesFailureType.unitNotFound => 'إحدى الوحدات غير متاحة.',
      SalesFailureType.insufficientStock =>
        'الرصيد غير كافٍ. يرجى تقليل الكمية أو تحديث المخزون.',
      SalesFailureType.invalidPayment =>
        'قيمة الدفع غير صحيحة. يرجى مراجعة المبلغ والطريقة.',
      SalesFailureType.invalidResponse =>
        'تعذّر قراءة البيانات. يرجى المحاولة مجددًا.',
      SalesFailureType.unknown =>
        'تعذّر إتمام البيع. يرجى المحاولة مرة أخرى.',
    };
