// lib/features/companies/presentation/providers/subscription_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/company.dart';
import '../../domain/entities/company_subscription.dart';
import 'company_context_provider.dart';
import 'company_context_state.dart';

/// Effective subscription of the currently selected company.
///
/// Derived from [companyContextProvider]; returns `null` while no company
/// is selected (which the router treats as "no guard").
final Provider<CompanySubscription?> subscriptionProvider =
    Provider<CompanySubscription?>((ref) {
  final Company? company = ref.watch(
    companyContextProvider.select(
      (CompanyContextState s) => s.currentCompany,
    ),
  );
  if (company == null) return null;
  return CompanySubscription.fromCompany(company);
});

/// Convenience: the current plan tier, or `null` while on trial.
final Provider<SubscriptionPlan?> currentPlanProvider =
    Provider<SubscriptionPlan?>((ref) {
  return ref.watch(subscriptionProvider)?.plan;
});

/// Whether the current company's subscription blocks write operations.
///
/// Safe default: `false` while no company is selected, so the router does
/// not accidentally redirect unauthenticated flows.
final Provider<bool> isSubscriptionBlockedProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionProvider)?.isBlocked ?? false;
});

/// Whether the current trial / paid period is within its last 3 days.
final Provider<bool> isSubscriptionExpiringSoonProvider =
    Provider<bool>((ref) {
  return ref.watch(subscriptionProvider)?.isExpiringSoon ?? false;
});

/// Whole days remaining in the current period, or `null` when N/A.
final Provider<int?> subscriptionDaysRemainingProvider =
    Provider<int?>((ref) {
  return ref.watch(subscriptionProvider)?.daysRemaining;
});
