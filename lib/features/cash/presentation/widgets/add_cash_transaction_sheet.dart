// lib/features/cash/presentation/widgets/add_cash_transaction_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/repositories/cash_repository.dart';
import '../providers/cash_providers.dart';

/// Bottom sheet for recording a manual cash movement.
///
/// The user picks the account, the direction (in / out), the category, and
/// the amount. Everything else is optional. On success the sheet closes and
/// returns the created [CashTransaction], or `null` when dismissed.
Future<CashTransaction?> showAddCashTransactionSheet({
  required BuildContext context,
  String? initialAccountId,
  CashDirection initialDirection = CashDirection.inFlow,
}) {
  return showModalBottomSheet<CashTransaction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext _) => _AddCashTransactionSheet(
      initialAccountId: initialAccountId,
      initialDirection: initialDirection,
    ),
  );
}

class _AddCashTransactionSheet extends ConsumerStatefulWidget {
  const _AddCashTransactionSheet({
    required this.initialAccountId,
    required this.initialDirection,
  });

  final String? initialAccountId;
  final CashDirection initialDirection;

  @override
  ConsumerState<_AddCashTransactionSheet> createState() =>
      _AddCashTransactionSheetState();
}

class _AddCashTransactionSheetState
    extends ConsumerState<_AddCashTransactionSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late CashDirection _direction;
  String? _accountId;
  String? _categoryId;
  bool _isSubmitting = false;
  CashFailureType? _failure;

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _direction = widget.initialDirection;
    _accountId = widget.initialAccountId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String? accountId = _accountId;
    if (accountId == null) {
      setState(() => _failure = CashFailureType.invalidInput);
      return;
    }

    final double amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _failure = CashFailureType.invalidInput);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _failure = null;
    });

    try {
      await ref.read(cashTransactionsProvider.notifier).addManual(
            accountId: accountId,
            categoryId: _categoryId,
            direction: _direction,
            amount: amount,
            reference: _emptyToNull(_referenceController.text),
            notes: _emptyToNull(_notesController.text),
            transactionDate: DateTime.now(),
          );

      if (!mounted) return;
      Navigator.of(context).pop(null); // caller refreshes via providers
    } on CashException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = e.type;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _failure = CashFailureType.unknown;
      });
    }
  }

  static String? _emptyToNull(String s) {
    final String t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final AsyncValue<List<CashAccount>> accountsAsync =
        ref.watch(cashAccountsProvider);
    final AsyncValue<List<CashCategory>> categoriesAsync =
        ref.watch(cashCategoriesProvider);

    final List<CashAccount> accounts =
        accountsAsync.valueOrNull ?? const <CashAccount>[];

    // Auto-select the first account if none chosen.
    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }

    final List<CashCategory> categories =
        (categoriesAsync.valueOrNull ?? const <CashCategory>[])
            .where((CashCategory c) {
      final bool isIncome = c.kind == CashCategoryKind.income;
      final bool isExpense = c.kind == CashCategoryKind.expense;
      return _direction == CashDirection.inFlow ? isIncome : isExpense;
    }).toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'إضافة حركة خزنة',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'سجّل عملية نقدية أو بطاقة يدويًا',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // ---- Direction ----
                SegmentedButton<CashDirection>(
                  segments: const <ButtonSegment<CashDirection>>[
                    ButtonSegment<CashDirection>(
                      value: CashDirection.inFlow,
                      label: Text('وارد'),
                      icon: Icon(Icons.arrow_downward, size: 16),
                    ),
                    ButtonSegment<CashDirection>(
                      value: CashDirection.outFlow,
                      label: Text('صادر'),
                      icon: Icon(Icons.arrow_upward, size: 16),
                    ),
                  ],
                  selected: <CashDirection>{_direction},
                  onSelectionChanged: _isSubmitting
                      ? null
                      : (Set<CashDirection> s) {
                          setState(() {
                            _direction = s.first;
                            _categoryId = null;
                          });
                        },
                ),
                const SizedBox(height: 16),

                // ---- Account ----
                if (accounts.isEmpty)
                  const _EmptyHint(
                    message: 'لا توجد حسابات. تواصل مع المالك.',
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _accountId,
                    decoration: const InputDecoration(
                      labelText: 'الحساب',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final CashAccount a in accounts)
                        DropdownMenuItem<String>(
                          value: a.id,
                          child: Text('${a.name} · ${a.type.label}'),
                        ),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (String? v) => setState(() => _accountId = v),
                  ),
                const SizedBox(height: 12),

                // ---- Amount ----
                TextFormField(
                  controller: _amountController,
                  enabled: !_isSubmitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                    suffixText: 'ج.م',
                  ),
                  validator: (String? v) {
                    final double? d = double.tryParse((v ?? '').trim());
                    if (d == null || d <= 0) {
                      return 'أدخل مبلغًا صحيحًا';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // ---- Category ----
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'التصنيف (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('بدون تصنيف'),
                    ),
                    for (final CashCategory c in categories)
                      DropdownMenuItem<String>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                  ],
                  onChanged: _isSubmitting
                      ? null
                      : (String? v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: 12),

                // ---- Reference ----
                TextFormField(
                  controller: _referenceController,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'المرجع (اختياري)',
                    hintText: 'رقم عملية، اسم مورد…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Notes ----
                TextFormField(
                  controller: _notesController,
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),

                if (_failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _FailureBanner(message: _failureMessage(_failure!)),
                ],

                const SizedBox(height: 20),

                AppButton(
                  label: _direction == CashDirection.inFlow
                      ? 'تسجيل الوارد'
                      : 'تسجيل الصادر',
                  icon: Icons.check_circle_outline,
                  expanded: true,
                  size: AppButtonSize.large,
                  isLoading: _isSubmitting,
                  onPressed: (_isSubmitting || accounts.isEmpty)
                      ? null
                      : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message),
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

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
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _failureMessage(CashFailureType type) => switch (type) {
      CashFailureType.network =>
        'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
      CashFailureType.unauthorized =>
        'لا تملك صلاحية لإضافة حركة خزنة.',
      CashFailureType.notFound => 'الحساب غير موجود.',
      CashFailureType.invalidInput =>
        'تحقق من المبلغ والحساب والتصنيف.',
      CashFailureType.invalidResponse =>
        'تعذّر قراءة البيانات من الخادم.',
      CashFailureType.unknown => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };
