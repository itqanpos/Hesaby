// lib/features/pos/presentation/dialogs/pos_payment_dialog.dart

import 'dart:typed_data';

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
import '../../../sales/domain/entities/sale_entities.dart';
import '../../../sales/domain/repositories/sales_repository.dart';
import '../../../sales/presentation/providers/sales_providers.dart';
import '../../../settings/data/services/company_logo_loader.dart';
import '../../../settings/domain/entities/print_style_settings.dart';
import '../../../settings/presentation/providers/company_settings_providers.dart';
import '../../../settings/presentation/providers/user_profile_providers.dart';
import '../../data/services/pdf_receipt_builder.dart';
import '../../data/services/pos_preferences.dart';
import '../../domain/entities/pos_cart.dart';
import '../../domain/entities/pos_cart_line.dart';
import '../../domain/entities/receipt.dart';
import '../providers/printer_providers.dart';
import '../state/pos_providers.dart';
import 'pos_print_preview_dialog.dart';

abstract final class PosPaymentMethod {
  static const String cash = 'cash';
  static const String card = 'card';
  static const String credit = 'credit';
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
  late final TextEditingController _amountController;

  String _method = PosPaymentMethod.cash;
  bool _isSubmitting = false;
  SalesFailureType? _serverFailure;

  @override
  void initState() {
    super.initState();
    _cart = ref.read(posCartProvider);
    _totals = ref.read(posTotalsProvider);
    _amountController = TextEditingController(
      text: _formatAmount(_settlementTotal),
    );
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (!mounted) return;
    setState(() => _serverFailure = null);
  }

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  double get _input => double.tryParse(_amountController.text.trim()) ?? 0;
  double get _saleTotal => _totals.total;
  double get _settlementTotal => _cart.customerBalance + _saleTotal;
  double get _newBalance => _settlementTotal - _input;

  bool get _hasBalanceChange =>
      _cart.hasCustomer && _newBalance != _cart.customerBalance;

  String? _paymentMethodForOffline() {
    if (_method == PosPaymentMethod.credit) return null;
    if (_method == PosPaymentMethod.card) return 'card';
    return 'cash';
  }

  String? _validationError() {
    if (_cart.isEmpty) return 'السلة فارغة. أضف منتجاً قبل الدفع.';
    if (_cart.discount > _cart.subtotal) {
      return 'الخصم أكبر من المجموع الفرعي للفاتورة.';
    }
    if (_saleTotal <= 0) {
      return 'إجمالي الفاتورة يجب أن يكون أكبر من صفر.';
    }

    if (_method == PosPaymentMethod.credit) {
      if (!_cart.hasCustomer) {
        return 'البيع الآجل يتطلب اختيار عميل مسجل.';
      }
      if (_input != 0) {
        return 'البيع الآجل لا يتطلب دفع أي مبلغ.';
      }
      return null;
    }

    if (_input < 0) {
      return 'المبلغ لا يمكن أن يكون سالبًا.';
    }

    if (_method == PosPaymentMethod.card) {
      if (_input < _saleTotal) {
        return 'الدفع بالبطاقة يجب أن يغطي كامل قيمة الفاتورة.';
      }
    }

    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
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
      final double input = _input;
      final double appliedToSale = input < saleTotal ? input : saleTotal;
      final double appliedToBalance =
          input > saleTotal ? (input - saleTotal) : 0;

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

      if (appliedToSale > 0) {
        final String method =
            _method == PosPaymentMethod.card ? 'card' : 'cash';
        await ref.read(cashRepositoryProvider).recordSalePayments(
              companyId: contextState.currentCompany?.id ?? '',
              saleId: confirmed.id,
              payments: <SalePaymentDraft>[
                SalePaymentDraft(amount: appliedToSale, method: method),
              ],
            );
      }

      if (appliedToBalance > 0 && _cart.customerId != null) {
        await ref.read(customersProvider.notifier).recordPayment(
              customerId: _cart.customerId!,
              amount: appliedToBalance,
              method: _method == PosPaymentMethod.card ? 'card' : 'cash',
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

      // ⬇️ التحقق من إعداد الطباعة المباشرة
      final bool directPrint = ref.read(companySettingsProvider).valueOrNull?.printDirectEnabled ?? false;
      final bool isDesktop = defaultTargetPlatform == TargetPlatform.windows || 
                             defaultTargetPlatform == TargetPlatform.linux || 
                             defaultTargetPlatform == TargetPlatform.macOS;
      final bool hasSavedPrinter = ref.read(savedPrinterProvider).valueOrNull != null;

      if (directPrint && isDesktop && hasSavedPrinter) {
        // تنفيذ الطباعة المباشرة
        try {
          final engine = ref.read(appPrintEngineProvider);
          final logo = await _loadLogoBytes();
          final style = _readStyle();
          
          final success = await engine.printThermal(
            receipt: receipt,
            paperWidthDots: _thermalWidthDots(),
            logoBytes: logo,
            style: style,
          );

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success 
                  ? 'تم إتمام البيع والطباعة المباشرة.' 
                  : 'تم إتمام البيع، لكن تعذّرت الطباعة المباشرة.'),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إتمام البيع، لكن حدث خطأ أثناء الطباعة.')),
          );
        }
      } else {
        // إظهار حوار المعاينة العادي
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) =>
              _PosReceiptDialog(receipt: receipt),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SaleException catch (error) {
      if (error.type == SalesFailureType.network && createdSale == null) {
        if (!mounted) return;
        await _submitOffline(
          contextState: contextState,
          branchId: branchId,
        );
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
      await _submitOffline(
        contextState: contextState,
        branchId: branchId,
      );
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
    final double input = _input;
    final double appliedToSale = input < saleTotal ? input : saleTotal;
    final double appliedToBalance =
        input > saleTotal ? (input - saleTotal) : 0;
    final String? paymentMethod = _paymentMethodForOffline();

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

    // ⬇️ التحقق من إعداد الطباعة المباشرة للأوفلاين
    final bool directPrint = ref.read(companySettingsProvider).valueOrNull?.printDirectEnabled ?? false;
    final bool isDesktop = defaultTargetPlatform == TargetPlatform.windows || 
                           defaultTargetPlatform == TargetPlatform.linux || 
                           defaultTargetPlatform == TargetPlatform.macOS;
    final bool hasSavedPrinter = ref.read(savedPrinterProvider).valueOrNull != null;

    if (directPrint && isDesktop && hasSavedPrinter) {
      // تنفيذ الطباعة المباشرة
      try {
        final engine = ref.read(appPrintEngineProvider);
        final logo = await _loadLogoBytes();
        final style = _readStyle();
        
        final success = await engine.printThermal(
          receipt: receipt,
          paperWidthDots: _thermalWidthDots(),
          logoBytes: logo,
          style: style,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
                ? 'تم الحفظ محلياً والطباعة المباشرة.' 
                : 'تم الحفظ محلياً، لكن تعذّرت الطباعة المباشرة.'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ محلياً، لكن حدث خطأ أثناء الطباعة.')),
        );
      }
    } else {
      // إظهار حوار المعاينة العادي
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => _PosReceiptDialog(
          receipt: receipt,
          isOffline: true,
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
    } catch (e) {
      return null;
    }
  }

  PrintStyleSettings _readStyle() {
    final settings = ref.read(companySettingsProvider).valueOrNull;
    if (settings == null) return const PrintStyleSettings.defaults();
    return PrintStyleSettings.fromCompanySettings(settings);
  }

  int _thermalWidthDots() {
    final size = ref.read(posPaperSizeProvider).valueOrNull ?? PosPreferences.defaultPaperSize;
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
      showTaxNumberOnPrint:
          ref.read(showTaxNumberOnPrintProvider),
      showCommercialRegisterOnPrint:
          ref.read(showCommercialRegisterOnPrintProvider),
      showCurrencySymbol:
          ref.read(showCurrencySymbolProvider),
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
      paidAmount: _input,
      customerName: _cart.customerName,
      customerAddress: customerAddress,
      customerPhone: customerPhone,
      cashierName: cashierName,
      previousBalance:
          _cart.hasCustomer ? _cart.customerBalance : null,
      newBalance: _cart.hasCustomer ? _newBalance : null,
      footer: ref.read(receiptFooterProvider),
    );
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      _serverFailure = null;
      if (method == PosPaymentMethod.credit) {
        _amountController.text = '0';
      } else if (method == PosPaymentMethod.card) {
        _amountController.text = _formatAmount(_saleTotal);
      } else {
        _amountController.text = _formatAmount(_settlementTotal);
      }
    });
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
                  Text('طريقة الدفع', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _MethodTile(
                          label: 'نقدي',
                          icon: Icons.payments_outlined,
                          selected: _method == PosPaymentMethod.cash,
                          enabled: !_isSubmitting,
                          onTap: () => _selectMethod(PosPaymentMethod.cash),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MethodTile(
                          label: 'بطاقة',
                          icon: Icons.credit_card,
                          selected: _method == PosPaymentMethod.card,
                          enabled: !_isSubmitting,
                          onTap: () => _selectMethod(PosPaymentMethod.card),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MethodTile(
                          label: 'آجل',
                          icon: Icons.schedule,
                          selected: _method == PosPaymentMethod.credit,
                          enabled: !_isSubmitting,
                          onTap: () =>
                              _selectMethod(PosPaymentMethod.credit),
                        ),
                      ),
                    ],
                  ),
                  if (_method != PosPaymentMethod.credit) ...<Widget>[
                    const SizedBox(height: 16),
                    Text('المبلغ المدفوع',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    _AmountField(
                      controller: _amountController,
                      enabled: !_isSubmitting,
                      hasError: displayError != null,
                    ),
                  ],
                  if (displayError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: displayError),
                  ],

                  const SizedBox(height: 16),
                  _BalanceResult(
                    hasCustomer: _cart.hasCustomer,
                    previousBalance: _cart.customerBalance,
                    newBalance: _newBalance,
                    hasBalanceChange: _hasBalanceChange,
                  ),

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

class _BalanceResult extends StatelessWidget {
  const _BalanceResult({
    required this.hasCustomer,
    required this.previousBalance,
    required this.newBalance,
    required this.hasBalanceChange,
  });

  final bool hasCustomer;
  final double previousBalance;
  final double newBalance;
  final bool hasBalanceChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (!hasCustomer) {
      return const SizedBox.shrink();
    }

    String label;
    Color color;
    double displayed;
    if (newBalance > 0) {
      label = 'الرصيد الجديد على العميل';
      color = scheme.error;
      displayed = newBalance;
    } else if (newBalance < 0) {
      label = 'الرصيد الجديد للعميل (له عندنا)';
      color = scheme.primary;
      displayed = newBalance.abs();
    } else {
      label = 'الرصيد الجديد';
      color = scheme.primary;
      displayed = 0;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (hasBalanceChange) ...<Widget>[
              _row(
                theme,
                scheme,
                'الرصيد السابق',
                AppFormatters.money(previousBalance.abs()),
              ),
              const Divider(height: 16),
            ],
            _row(
              theme,
              scheme,
              label,
              AppFormatters.money(displayed),
              emphasized: true,
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    ColorScheme scheme,
    String label,
    String value, {
    bool emphasized = false,
    Color? color,
  }) {
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

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.enabled,
    required this.hasError,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return TextField(
      controller: controller,
      enabled: enabled,
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        hintText: '0',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: hasError ? scheme.error : scheme.outline,
            width: hasError ? 2 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: hasError ? scheme.error : scheme.primary,
            width: 2,
          ),
        ),
      ),
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
            Icon(
              Icons.error_outline,
              color: scheme.onErrorContainer,
              size: 20,
            ),
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

class _PosReceiptDialog extends ConsumerWidget {
  const _PosReceiptDialog({
    required this.receipt,
    this.isOffline = false,
  });

  final Receipt receipt;
  final bool isOffline;

  Future<void> _handlePrint(BuildContext context, WidgetRef ref) async {
    if (!context.mounted) return;
    await showPosPrintPreviewDialog(
      context: context,
      receipt: receipt,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      isOffline
                          ? Icons.cloud_off_outlined
                          : Icons.check_circle,
                      color: scheme.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isOffline
                            ? 'تم حفظ البيع محليًا'
                            : 'تم إتمام البيع',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),

                if (isOffline) ...<Widget>[
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
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
                            Icons.schedule,
                            size: 18,
                            color: scheme.onTertiaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'سيُرسل تلقائيًا عند عودة الاتصال. '
                              'رقم الفاتورة سيُحدَّد على الخادم.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                if (!isOffline && receipt.invoiceNumber != null)
                  Text(
                    'الإيصال: ${receipt.invoiceNumber}',
                    style: theme.textTheme.bodyMedium,
                  ),
                Text(
                  AppFormatters.dateTime(receipt.dateTime),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  receipt.customerName ?? 'عميل نقدي',
                  style: theme.textTheme.bodyMedium,
                ),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                for (final ReceiptLine line in receipt.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            line.productName,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${AppFormatters.quantity(line.quantity)} × '
                          '${AppFormatters.money(line.unitPrice)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppFormatters.money(line.lineTotal),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

                _row(theme, 'المجموع الفرعي',
                    AppFormatters.money(receipt.subtotal)),
                if (receipt.discount > 0)
                  _row(theme, 'الخصم',
                      AppFormatters.money(receipt.discount)),
                if (receipt.taxAmount > 0)
                  _row(theme, 'الضريبة',
                      AppFormatters.money(receipt.taxAmount)),
                _row(theme, 'الإجمالي',
                    AppFormatters.money(receipt.total),
                    emphasized: true),
                _row(theme, 'المدفوع',
                    AppFormatters.money(receipt.paidAmount)),

                if (receipt.hasBalanceChange) ...<Widget>[
                  const SizedBox(height: 6),
                  _row(theme, 'الرصيد السابق',
                      AppFormatters.money(receipt.previousBalance!.abs()),
                      color: (receipt.previousBalance ?? 0) > 0
                          ? scheme.error
                          : scheme.primary),
                  if (receipt.hasCreditBalance)
                    _row(
                      theme,
                      'الرصيد الجديد (له عندنا)',
                      AppFormatters.money(receipt.newBalanceAbsolute),
                      color: scheme.primary,
                      emphasized: true,
                    )
                  else
                    _row(
                      theme,
                      'الرصيد الجديد على العميل',
                      AppFormatters.money(receipt.newBalanceAbsolute),
                      color: receipt.newBalanceAbsolute == 0
                          ? scheme.primary
                          : scheme.error,
                      emphasized: true,
                    ),
                ],

                const SizedBox(height: 16),

                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppButton(
                        label: 'طباعة',
                        icon: Icons.print_outlined,
                        onPressed: () => _handlePrint(context, ref),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'فاتورة جديدة',
                        icon: Icons.add,
                        variant: AppButtonVariant.outline,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    bool emphasized = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            value,
            style: (emphasized
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium)
                ?.copyWith(
              color: color ??
                  (emphasized ? theme.colorScheme.primary : null),
              fontWeight: emphasized ? FontWeight.w700 : null,
            ),
          ),
        ],
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
