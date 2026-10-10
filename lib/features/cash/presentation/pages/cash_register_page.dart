// lib/features/cash/presentation/pages/cash_register_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_empty.dart';
import '../../../../shared/widgets/app_error.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/repositories/cash_repository.dart';
import '../providers/cash_providers.dart';
import '../widgets/add_cash_transaction_sheet.dart';

/// Cash register main page.
///
/// Layout:
/// * Total balance card + per-account balance cards.
/// * Quick actions (record income / record expense).
/// * Recent transactions list, most recent first.
///
/// All writes go through [CashTransactionsNotifier] which invalidates the
/// overview so the balance cards refresh automatically.
class CashRegisterPage extends ConsumerStatefulWidget {
  const CashRegisterPage({super.key});

  @override
  ConsumerState<CashRegisterPage> createState() => _CashRegisterPageState();
}

class _CashRegisterPageState extends ConsumerState<CashRegisterPage> {
  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'ج.م ',
    decimalDigits: 2,
  );
  static final DateFormat _dateTime = DateFormat('yyyy/MM/dd HH:mm');

  Future<void> _refresh() async {
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(cashTransactionsProvider);
    ref.invalidate(cashAccountsProvider);
    ref.invalidate(cashCategoriesProvider);
    await Future.wait(<Future<void>>[
      ref.read(cashOverviewProvider.future),
      ref.read(cashTransactionsProvider.future),
    ]);
  }

  Future<void> _addMovement(CashDirection direction) async {
    await showAddCashTransactionSheet(
      context: context,
      initialDirection: direction,
    );
    // Providers invalidate themselves; nothing else to do.
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CashOverview> overviewAsync =
        ref.watch(cashOverviewProvider);
    final AsyncValue<List<CashTransaction>> txAsync =
        ref.watch(cashTransactionsProvider);

    final Object? firstError = overviewAsync.error ?? txAsync.error;
    final bool anyLoading =
        (overviewAsync.isLoading && !overviewAsync.hasValue) ||
            (txAsync.isLoading && !txAsync.hasValue);

    return AppShell(
      appBar: AppBar(
        title: const Text('الخزنة'),
        actions: <Widget>[
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: anyLoading ? null : _refresh,
          ),
        ],
      ),
      body: Builder(
        builder: (BuildContext _) {
          if (anyLoading) return const AppLoader();

          if (firstError != null && !overviewAsync.hasValue) {
            return AppErrorView(
              title: 'تعذّر تحميل الخزنة',
              message: firstError is CashException
                  ? _errorMessage(firstError.type)
                  : 'حدث خطأ غير متوقع.',
              retryLabel: 'إعادة المحاولة',
              onRetry: _refresh,
            );
          }

          final CashOverview overview = overviewAsync.valueOrNull ??
              const CashOverview.empty();
          final List<CashTransaction> tx =
              txAsync.valueOrNull ?? const <CashTransaction>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              children: <Widget>[
                _TotalBalanceCard(
                  total: overview.totalBalance,
                  money: _money,
                ),
                const SizedBox(height: 12),
                if (overview.balances.isEmpty)
                  const AppEmptyView(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'لا توجد حسابات',
                    message: 'لم يتم إعداد حسابات الخزنة بعد.',
                  )
                else
                  _AccountsGrid(balances: overview.balances, money: _money),
                const SizedBox(height: 20),
                _QuickActions(
                  onIncome: () => _addMovement(CashDirection.inFlow),
                  onExpense: () => _addMovement(CashDirection.outFlow),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.history, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'آخر الحركات',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (tx.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: AppEmptyView(
                      icon: Icons.receipt_long_outlined,
                      title: 'لا توجد حركات',
                      message: 'لم يتم تسجيل أي حركة بعد.',
                    ),
                  )
                else
                  Column(
                    children: <Widget>[
                      for (int i = 0; i < tx.length; i++) ...<Widget>[
                        _TransactionTile(
                          transaction: tx[i],
                          money: _money,
                          dateTime: _dateTime,
                        ),
                        if (i < tx.length - 1) const SizedBox(height: 6),
                      ],
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _errorMessage(CashFailureType type) => switch (type) {
        CashFailureType.network =>
          'تعذّر الاتصال بالخادم. تحقق من اتصالك.',
        CashFailureType.unauthorized =>
          'لا تملك صلاحية عرض الخزنة.',
        CashFailureType.notFound => 'الحساب غير موجود.',
        CashFailureType.invalidInput => 'بيانات غير صحيحة.',
        CashFailureType.invalidResponse =>
          'تعذّر قراءة البيانات من الخادم.',
        CashFailureType.unknown => 'حدث خطأ غير متوقع.',
      };
}

// ============================================================================
// Total balance
// ============================================================================

class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({required this.total, required this.money});

  final double total;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool positive = total >= 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: positive
              ? <Color>[scheme.primary, scheme.tertiary]
              : <Color>[scheme.error, scheme.errorContainer],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: (positive ? scheme.primary : scheme.error)
                .withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'الرصيد الإجمالي',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              money.format(total),
              style: theme.textTheme.displaySmall?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Accounts grid
// ============================================================================

class _AccountsGrid extends StatelessWidget {
  const _AccountsGrid({required this.balances, required this.money});

  final List<CashAccountBalance> balances;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < balances.length; i++) ...<Widget>[
          Expanded(
            child: _AccountCard(
              balance: balances[i],
              money: money,
            ),
          ),
          if (i < balances.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.balance, required this.money});

  final CashAccountBalance balance;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final IconData icon = switch (balance.account.type) {
      CashAccountType.cash => Icons.payments_outlined,
      CashAccountType.card => Icons.credit_card,
      CashAccountType.bank => Icons.account_balance_outlined,
      CashAccountType.instapay => Icons.phone_iphone,
      CashAccountType.other => Icons.account_balance_wallet_outlined,
    };

    final Color accent = switch (balance.account.type) {
      CashAccountType.cash => const Color(0xFF0F7B6C),
      CashAccountType.card => const Color(0xFF0288D1),
      CashAccountType.bank => const Color(0xFF6A1B9A),
      CashAccountType.instapay => const Color(0xFFEF6C00),
      CashAccountType.other => scheme.primary,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    balance.account.name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              money.format(balance.balance),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: balance.balance < 0 ? scheme.error : accent,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Quick actions
// ============================================================================

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onIncome, required this.onExpense});

  final VoidCallback onIncome;
  final VoidCallback onExpense;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: AppButton(
            label: 'وارد',
            icon: Icons.arrow_downward,
            variant: AppButtonVariant.secondary,
            expanded: true,
            onPressed: onIncome,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppButton(
            label: 'صادر',
            icon: Icons.arrow_upward,
            variant: AppButtonVariant.secondary,
            expanded: true,
            onPressed: onExpense,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Transaction tile
// ============================================================================

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.money,
    required this.dateTime,
  });

  final CashTransaction transaction;
  final NumberFormat money;
  final DateFormat dateTime;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isIn = transaction.direction == CashDirection.inFlow;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isIn ? scheme.primary : scheme.error)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isIn ? Icons.arrow_downward : Icons.arrow_upward,
                color: isIn ? scheme.primary : scheme.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    transaction.categoryName ??
                        _sourceLabel(transaction.sourceType),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${transaction.accountName} · '
                    '${dateTime.format(transaction.transactionDate.toLocal())}',
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
            Text(
              '${isIn ? '+' : '-'}${money.format(transaction.amount)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: isIn ? scheme.primary : scheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _sourceLabel(String sourceType) => switch (sourceType) {
        'sale' => 'بيع',
        'sale_return' => 'مرتجع بيع',
        'purchase' => 'مشتريات',
        'purchase_return' => 'مرتجع شراء',
        'customer_payment' => 'دفعة عميل',
        'customer_refund' => 'استرداد لعميل',
        'supplier_payment' => 'دفعة مورد',
        'supplier_refund' => 'استرداد من مورد',
        'expense' => 'مصروف',
        'salary' => 'راتب',
        'advance' => 'سلفة',
        'transfer' => 'تحويل',
        'opening' => 'رصيد افتتاحي',
        'manual' => 'حركة يدوية',
        _ => sourceType,
      };
}
