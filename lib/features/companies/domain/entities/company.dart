// lib/features/companies/domain/entities/company.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents a tenant company inside HESABI.
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
    this.taxNumber,
    this.commercialRegister,
    this.subscriptionStatus = 'trial',
    this.trialEndsAt,
    this.subscriptionStartedAt,
    this.planId,
    this.billingCycle,
    this.subscribedUntil,
    this.isSuspended = false,
    this.suspensionReason,
    this.maxUsers = 5,
    this.maxBranches = 1,
  });

  final String id;
  final String name;
  final String? legalName;
  final String? phone;
  final String? email;
  final String? address;

  /// Tax registration number (الرقم الضريبي).
  final String? taxNumber;

  /// Commercial register number (السجل التجاري).
  final String? commercialRegister;

  final String currency;
  final String timezone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ---- Subscription ----

  final String subscriptionStatus;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionStartedAt;
  final String? planId;
  final String? billingCycle;
  final DateTime? subscribedUntil;

  // ---- Suspension & Limits ----

  final bool isSuspended;
  final String? suspensionReason;
  final int maxUsers;
  final int maxBranches;

  // ---------------------------------------------------------------------------
  // Convenience
  // ---------------------------------------------------------------------------

  bool get hasTaxNumber =>
      taxNumber != null && taxNumber!.trim().isNotEmpty;

  bool get hasCommercialRegister =>
      commercialRegister != null && commercialRegister!.trim().isNotEmpty;

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Company copyWith({
    String? name,
    String? legalName,
    bool clearLegalName = false,
    String? phone,
    bool clearPhone = false,
    String? email,
    bool clearEmail = false,
    String? address,
    bool clearAddress = false,
    String? taxNumber,
    bool clearTaxNumber = false,
    String? commercialRegister,
    bool clearCommercialRegister = false,
    String? currency,
    String? timezone,
    bool? isActive,
    DateTime? updatedAt,
    // Suspension & Limits
    bool? isSuspended,
    String? suspensionReason,
    bool clearSuspensionReason = false,
    int? maxUsers,
    int? maxBranches,
  }) {
    return Company(
      id: id,
      name: name ?? this.name,
      legalName: clearLegalName ? null : (legalName ?? this.legalName),
      phone: clearPhone ? null : (phone ?? this.phone),
      email: clearEmail ? null : (email ?? this.email),
      address: clearAddress ? null : (address ?? this.address),
      taxNumber: clearTaxNumber ? null : (taxNumber ?? this.taxNumber),
      commercialRegister: clearCommercialRegister
          ? null
          : (commercialRegister ?? this.commercialRegister),
      currency: currency ?? this.currency,
      timezone: timezone ?? this.timezone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      subscriptionStatus: subscriptionStatus,
      trialEndsAt: trialEndsAt,
      subscriptionStartedAt: subscriptionStartedAt,
      planId: planId,
      billingCycle: billingCycle,
      subscribedUntil: subscribedUntil,
      isSuspended: isSuspended ?? this.isSuspended,
      suspensionReason:
          clearSuspensionReason ? null : (suspensionReason ?? this.suspensionReason),
      maxUsers: maxUsers ?? this.maxUsers,
      maxBranches: maxBranches ?? this.maxBranches,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        legalName,
        phone,
        email,
        address,
        taxNumber,
        commercialRegister,
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
        isSuspended,
        suspensionReason,
        maxUsers,
        maxBranches,
      ];

  @override
  String toString() =>
      'Company(id: $id, name: $name, isActive: $isActive, '
      'subscriptionStatus: $subscriptionStatus, planId: $planId, '
      'isSuspended: $isSuspended, maxUsers: $maxUsers, maxBranches: $maxBranches)';
}
