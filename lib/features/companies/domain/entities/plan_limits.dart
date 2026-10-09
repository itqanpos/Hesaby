// lib/features/companies/domain/entities/plan_limits.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'company_subscription.dart';

/// Hard limits and pricing for each plan tier.
///
/// Single source of truth shared between the UI (subscription page,
/// enforcement dialogs) and any future server-side validation.
abstract final class PlanLimits {
  // ---- Users ----
  static const int basicUsers = 3;
  static const int proUsers = 10;

  // ---- Products ----
  static const int basicProducts = 500;
  static const int proProducts = 2000;

  // ---- Branches ----
  static const int basicBranches = 1;
  static const int proBranches = 3;

  // ---- Pricing (EGP) ----
  static const int basicMonthly = 500;
  static const int basicYearly = 5000;
  static const int proMonthly = 750;
  static const int proYearly = 7500;

  // ---- Accessors ----

  /// Maximum number of active members allowed on [plan].
  ///
  /// Trial accounts use the Pro limits so testers can evaluate everything.
  static int usersFor(SubscriptionPlan? plan) =>
      plan == SubscriptionPlan.basic ? basicUsers : proUsers;

  static int productsFor(SubscriptionPlan? plan) =>
      plan == SubscriptionPlan.basic ? basicProducts : proProducts;

  static int branchesFor(SubscriptionPlan? plan) =>
      plan == SubscriptionPlan.basic ? basicBranches : proBranches;

  /// Monthly price in EGP.
  static int monthlyPrice(SubscriptionPlan plan) =>
      plan == SubscriptionPlan.basic ? basicMonthly : proMonthly;

  /// Yearly price in EGP.
  static int yearlyPrice(SubscriptionPlan plan) =>
      plan == SubscriptionPlan.basic ? basicYearly : proYearly;

  /// Price for [plan] under [cycle].
  static int price(SubscriptionPlan plan, BillingCycle cycle) =>
      cycle == BillingCycle.yearly
          ? yearlyPrice(plan)
          : monthlyPrice(plan);
}

/// Immutable snapshot of a plan's public description. Used by the
/// subscription page.
@immutable
class PlanDescription extends Equatable {
  const PlanDescription({
    required this.plan,
    required this.name,
    required this.tagline,
    required this.users,
    required this.products,
    required this.branches,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.highlight,
  });

  final SubscriptionPlan plan;
  final String name;
  final String tagline;
  final int users;
  final int products;
  final int branches;
  final int monthlyPrice;
  final int yearlyPrice;
  final bool highlight;

  static const List<PlanDescription> all = <PlanDescription>[
    PlanDescription(
      plan: SubscriptionPlan.basic,
      name: 'الأساسية',
      tagline: 'مثالي للمتاجر الصغيرة',
      users: PlanLimits.basicUsers,
      products: PlanLimits.basicProducts,
      branches: PlanLimits.basicBranches,
      monthlyPrice: PlanLimits.basicMonthly,
      yearlyPrice: PlanLimits.basicYearly,
      highlight: false,
    ),
    PlanDescription(
      plan: SubscriptionPlan.pro,
      name: 'برو',
      tagline: 'للمتاجر المتنامية متعددة الفروع',
      users: PlanLimits.proUsers,
      products: PlanLimits.proProducts,
      branches: PlanLimits.proBranches,
      monthlyPrice: PlanLimits.proMonthly,
      yearlyPrice: PlanLimits.proYearly,
      highlight: true,
    ),
  ];

  @override
  List<Object?> get props => <Object?>[plan];
}
