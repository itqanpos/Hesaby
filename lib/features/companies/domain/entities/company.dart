// lib/features/companies/domain/entities/company.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a tenant company inside HESABI.
///
/// Subscription fields mirror the columns on `public.companies`. They are
/// optional in the constructor with sensible defaults so existing call
/// sites (tests, widget previews) keep compiling without changes.
@immutable
class Company extends Equatable {
  const Company({
    required this.id,
    required this.name,
    required this.currency,
    required this.timezone,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.legalName,
    this.phone,
    this.email,
    this.address,
    this.subscriptionStatus = 'trial',
    this.trialEndsAt,
    this.subscriptionStartedAt,
    this.planId,
    this.billingCycle,
    this.subscribedUntil,
  });

  final String id;
  final String name;
  final String? legalName;
  final String? phone;
  final String? email;
  final String? address;
  final String currency;
  final String timezone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ---- Subscription ----

  /// Raw status stored in the database.
  ///
  /// One of `trial` / `active` / `expired` / `cancelled`. Prefer
  /// `CompanySubscription.effectiveStatus` (which folds in the dates) for
  /// any access decision.
  final String subscriptionStatus;

  /// When the 7-day free trial ends. Meaningful only while
  /// [subscriptionStatus] is `trial`.
  final DateTime? trialEndsAt;

  /// When the trial (or the very first paid period) started.
  final DateTime? subscriptionStartedAt;

  /// `basic` | `pro` — null while on trial.
  final String? planId;

  /// `monthly` | `yearly` — null while on trial.
  final String? billingCycle;

  /// End of the current paid period. Meaningful only while
  /// [subscriptionStatus] is `active`.
  final DateTime? subscribedUntil;

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        legalName,
        phone,
        email,
        address,
        currency,
        timezone,
        isActive,
        createdAt,
        updatedAt,
        subscriptionStatus,
        trialEndsAt,
        subscriptionStartedAt,
        planId,
        billingCycle,
        subscribedUntil,
      ];

  @override
  String toString() =>
      'Company(id: $id, name: $name, isActive: $isActive, '
      'subscriptionStatus: $subscriptionStatus, planId: $planId)';
}
