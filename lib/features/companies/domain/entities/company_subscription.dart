// lib/features/companies/domain/entities/company_subscription.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'company.dart';

/// Effective status of a company's subscription.
///
/// The database stores raw fields; this enum is the **computed** result
/// that the app uses everywhere for access decisions.
enum SubscriptionStatus {
  /// Within the 7-day free trial window.
  trial,

  /// A paid period is currently active.
  active,

  /// Trial or paid period is over. Company is read-only.
  expired,

  /// Subscription was explicitly cancelled by the operator.
  cancelled,
}

/// Subscription plan tiers.
enum SubscriptionPlan {
  basic,
  pro;

  /// Arabic display label.
  String get label => this == SubscriptionPlan.pro ? 'برو' : 'الأساسية';
}

/// Billing cycle for paid plans.
enum BillingCycle {
  monthly,
  yearly;

  /// Arabic display label.
  String get label => this == BillingCycle.yearly ? 'سنوي' : 'شهري';
}

/// Pure-Dart view of a company's subscription.
///
/// Computed from the raw fields on [Company]. Contains every derived value
/// the UI needs (remaining days, blocked status, plan limits) so that no
/// page has to re-implement the same logic.
@immutable
class CompanySubscription extends Equatable {
  const CompanySubscription({
    required this.status,
    this.plan,
    this.billingCycle,
    this.trialEndsAt,
    this.subscribedUntil,
    this.startedAt,
  });

  /// Builds a subscription from a company row.
  ///
  /// This is the single source of truth for the "effective status" rule:
  /// * raw `active` + `subscribedUntil` in the future → **active**.
  /// * raw `active` + `subscribedUntil` in the past  → **expired**.
  /// * raw `trial`  + `trialEndsAt` in the future    → **trial**.
  /// * raw `trial`  + `trialEndsAt` in the past      → **expired**.
  /// * raw `expired` or `cancelled`                  → passed through.
  factory CompanySubscription.fromCompany(Company company) {
    final SubscriptionStatus raw = _parseStatus(company.subscriptionStatus);
    final DateTime now = DateTime.now().toUtc();

    SubscriptionStatus effective;
    switch (raw) {
      case SubscriptionStatus.active:
        final DateTime? until = company.subscribedUntil;
        effective = (until != null && until.isAfter(now))
            ? SubscriptionStatus.active
            : SubscriptionStatus.expired;
      case SubscriptionStatus.trial:
        final DateTime? until = company.trialEndsAt;
        effective = (until != null && until.isAfter(now))
            ? SubscriptionStatus.trial
            : SubscriptionStatus.expired;
      case SubscriptionStatus.expired:
      case SubscriptionStatus.cancelled:
        effective = raw;
    }

    return CompanySubscription(
      status: effective,
      plan: _parsePlan(company.planId),
      billingCycle: _parseBillingCycle(company.billingCycle),
      trialEndsAt: company.trialEndsAt,
      subscribedUntil: company.subscribedUntil,
      startedAt: company.subscriptionStartedAt,
    );
  }

  /// Effective status.
  final SubscriptionStatus status;

  /// Plan tier, or `null` while on trial.
  final SubscriptionPlan? plan;

  /// Billing cycle, or `null` while on trial.
  final BillingCycle? billingCycle;

  /// When the trial ends. Only meaningful for [status] `trial`.
  final DateTime? trialEndsAt;

  /// End of the paid period. Only meaningful for [status] `active`.
  final DateTime? subscribedUntil;

  /// When the subscription (trial or first paid period) started.
  final DateTime? startedAt;

  // ---------------------------------------------------------------------------
  // Derived — state
  // ---------------------------------------------------------------------------

  bool get isTrial => status == SubscriptionStatus.trial;
  bool get isActive => status == SubscriptionStatus.active;
  bool get isExpired =>
      status == SubscriptionStatus.expired ||
      status == SubscriptionStatus.cancelled;
  bool get isCancelled => status == SubscriptionStatus.cancelled;

  /// Whether the app must block write operations.
  bool get isBlocked => isExpired;

  /// Whether the account is active enough to allow normal use.
  bool get hasAccess => !isBlocked;

  /// Whole days remaining in the current period, or `null` when the
  /// account is not in a time-boxed state.
  int? get daysRemaining {
    final DateTime now = DateTime.now().toUtc();
    final DateTime? end =
        isTrial ? trialEndsAt : (isActive ? subscribedUntil : null);
    if (end == null) return null;
    final int days = end.difference(now).inDays;
    return days < 0 ? 0 : days;
  }

  /// Whether the account is within its last 3 days (trial or paid).
  bool get isExpiringSoon {
    final int? d = daysRemaining;
    return d != null && d <= 3;
  }

  // ---------------------------------------------------------------------------
  // Copy helpers
  // ---------------------------------------------------------------------------

  CompanySubscription copyWith({
    SubscriptionStatus? status,
    SubscriptionPlan? plan,
    BillingCycle? billingCycle,
    DateTime? trialEndsAt,
    DateTime? subscribedUntil,
    DateTime? startedAt,
  }) {
    return CompanySubscription(
      status: status ?? this.status,
      plan: plan ?? this.plan,
      billingCycle: billingCycle ?? this.billingCycle,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      subscribedUntil: subscribedUntil ?? this.subscribedUntil,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        status,
        plan,
        billingCycle,
        trialEndsAt,
        subscribedUntil,
        startedAt,
      ];

  @override
  String toString() =>
      'CompanySubscription(status: ${status.name}, plan: ${plan?.name}, '
      'daysRemaining: $daysRemaining)';

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

  static SubscriptionStatus _parseStatus(String raw) {
    switch (raw) {
      case 'active':
        return SubscriptionStatus.active;
      case 'expired':
        return SubscriptionStatus.expired;
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      case 'trial':
      default:
        return SubscriptionStatus.trial;
    }
  }

  static SubscriptionPlan? _parsePlan(String? raw) {
    switch (raw) {
      case 'basic':
        return SubscriptionPlan.basic;
      case 'pro':
        return SubscriptionPlan.pro;
      default:
        return null;
    }
  }

  static BillingCycle? _parseBillingCycle(String? raw) {
    switch (raw) {
      case 'monthly':
        return BillingCycle.monthly;
      case 'yearly':
        return BillingCycle.yearly;
      default:
        return null;
    }
  }
}
