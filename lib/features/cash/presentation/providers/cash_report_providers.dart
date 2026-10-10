// lib/features/cash/presentation/providers/cash_report_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../companies/presentation/providers/company_context_provider.dart';
import '../../../companies/presentation/providers/company_context_state.dart';
import '../../domain/entities/cash_entities.dart';
import '../../domain/entities/cash_report_entities.dart';
import 'cash_providers.dart';

// ---------------------------------------------------------------------------
// Period selection
// ---------------------------------------------------------------------------

/// Selected period for cash reports. Defaults to "this month".
class CashReportPeriodNotifier extends Notifier<CashReportPeriod> {
  @override
  CashReportPeriod build() =>
      CashReportPeriod.preset(CashReportPeriodType.thisMonth);

  void setType(CashReportPeriodType type) {
    state = CashReportPeriod.preset(type);
  }

  void setCustom(DateTime from, DateTime to) {
    state = CashReportPeriod(
      type: CashReportPeriodType.thisMonth, // ignored by label getter
      from: from,
      to: to,
    );
  }
}

final NotifierProvider<CashReportPeriodNotifier, CashReportPeriod>
    cashReportPeriodProvider =
    NotifierProvider<CashReportPeriodNotifier, CashReportPeriod>(
  CashReportPeriodNotifier.new,
);

// ---------------------------------------------------------------------------
// Report computation
// ---------------------------------------------------------------------------

class CashReportsNotifier extends AsyncNotifier<CashReportBundle> {
  @override
  Future<CashReportBundle> build() async {
    final String? companyId = ref.watch(
      companyContextProvider.select(
        (CompanyContextState s) => s.currentCompany?.id,
      ),
    );
    final CashReportPeriod period = ref.watch(cashReportPeriodProvider);

    if (companyId == null) {
      return CashReportBundle.empty(period);
    }

    // Fetch everything once — the dataset is small enough to aggregate
    // client-side, and this avoids maintaining an RPC per report.
    final List<CashTransaction> all =
        await ref.read(cashRepositoryProvider).listTransactions(
              companyId: companyId,
              limit: 20000,
            );

    return _compute(all, period);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  // ---------------------------------------------------------------------------
  // Aggregation
  // ---------------------------------------------------------------------------

  static CashReportBundle _compute(
    List<CashTransaction> all,
    CashReportPeriod period,
  ) {
    final DateTime? from = period.from;
    final DateTime? to = period.to;

    // Opening balance = net of every transaction strictly before `from`.
    double opening = 0;
    if (from != null) {
      for (final CashTransaction t in all) {
        if (t.transactionDate.isBefore(from)) {
          opening += t.signedAmount;
        }
      }
    }

    // In-period transactions.
    final List<CashTransaction> inPeriod = all.where((CashTransaction t) {
      if (from != null && t.transactionDate.isBefore(from)) return false;
      if (to != null && t.transactionDate.isAfter(to)) return false;
      return true;
    }).toList(growable: false);

    double totalIn = 0;
    double totalOut = 0;

    // Category aggregation.
    final Map<String, _CatAcc> catMap = <String, _CatAcc>{};

    // Account aggregation.
    final Map<String, _AccAcc> accMap = <String, _AccAcc>{};

    for (final CashTransaction t in inPeriod) {
      final bool isIn = t.direction == CashDirection.inFlow;
      if (isIn) {
        totalIn += t.amount;
      } else {
        totalOut += t.amount;
      }

      // ---- Category ----
      final String catName = t.categoryName ?? 'بدون تصنيف';
      final _CatAcc cat = catMap.putIfAbsent(catName, () => _CatAcc());
      if (isIn) {
        cat.inflow += t.amount;
      } else {
        cat.outflow += t.amount;
      }
      cat.count++;

      // ---- Account ----
      final _AccAcc acc = accMap.putIfAbsent(
        t.accountId,
        () => _AccAcc(name: t.accountName),
      );
      if (isIn) {
        acc.inflow += t.amount;
      } else {
        acc.outflow += t.amount;
      }
      acc.count++;
    }

    // Sorted category breakdown — by total (in+out) desc.
    final List<CashCategoryBreakdown> byCategory = catMap.entries
        .map(
          (MapEntry<String, _CatAcc> e) => CashCategoryBreakdown(
            categoryName: e.key,
            totalIn: e.value.inflow,
            totalOut: e.value.outflow,
            count: e.value.count,
          ),
        )
        .toList()
      ..sort((CashCategoryBreakdown a, CashCategoryBreakdown b) =>
          b.total.compareTo(a.total));

    final List<CashAccountBreakdown> byAccount = accMap.entries
        .map(
          (MapEntry<String, _AccAcc> e) => CashAccountBreakdown(
            accountId: e.key,
            accountName: e.value.name,
            totalIn: e.value.inflow,
            totalOut: e.value.outflow,
            count: e.value.count,
          ),
        )
        .toList()
      ..sort((CashAccountBreakdown a, CashAccountBreakdown b) =>
          b.totalIn.compareTo(a.totalIn));

    return CashReportBundle(
      period: period,
      summary: CashFlowSummary(
        openingBalance: opening,
        totalIn: totalIn,
        totalOut: totalOut,
        transactionCount: inPeriod.length,
      ),
      byCategory: byCategory,
      byAccount: byAccount,
    );
  }
}

final AsyncNotifierProvider<CashReportsNotifier, CashReportBundle>
    cashReportsProvider =
    AsyncNotifierProvider<CashReportsNotifier, CashReportBundle>(
  CashReportsNotifier.new,
);

// ---------------------------------------------------------------------------
// Mutable accumulators (private, throwaway)
// ---------------------------------------------------------------------------

class _CatAcc {
  double inflow = 0;
  double outflow = 0;
  int count = 0;
}

class _AccAcc {
  _AccAcc({required this.name});

  final String name;
  double inflow = 0;
  double outflow = 0;
  int count = 0;
}
