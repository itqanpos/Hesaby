// lib/features/admin/presentation/dialogs/admin_company_actions_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../companies/domain/entities/company.dart';
import '../../../companies/domain/entities/company_subscription.dart';
import '../../../companies/domain/entities/plan_limits.dart';

/// The action the admin chose in [showAdminCompanyActionsDialog].
enum AdminSubscriptionAction {
  /// Activate a fresh subscription or extend the current one.
  activateOrExtend,

  /// Mark the company as cancelled (read-only until renewed).
  cancel,
}

/// The result of the admin actions dialog.
class AdminSubscriptionChoice {
  const AdminSubscriptionChoice({
    required this.action,
    this.planId,
    this.billingCycle,
  });

  final AdminSubscriptionAction action;

  /// `basic` | `pro` — only set when [action] is `activateOrExtend`.
  final String? planId;

  /// `monthly` | `yearly` — only set when [action] is `activateOrExtend`.
  final String? billingCycle;
}

/// Opens the admin dialog used to change a company's subscription.
///
/// Returns `null` when the admin dismisses the dialog without confirming.
Future<AdminSubscriptionChoice?> showAdminCompanyActionsDialog({
  required BuildContext context,
  required Company company,
}) {
  return showDialog<AdminSubscriptionChoice>(
    context: context,
    builder: (BuildContext _) => _AdminCompanyActionsDialog(company: company),
  );
}

// ============================================================================
// Dialog
// ============================================================================

class _AdminCompanyActionsDialog extends StatefulWidget {
  const _AdminCompanyActionsDialog({required this.company});

  final Company company;

  @override
  State<_AdminCompanyActionsDialog> createState() =>
      _AdminCompanyActionsDialogState();
}

class _AdminCompanyActionsDialogState
    extends State<_AdminCompanyActionsDialog> {
  static final DateFormat _date = DateFormat('yyyy-MM-dd');

  SubscriptionPlan _plan = SubscriptionPlan.pro;
  BillingCycle _cycle = BillingCycle.yearly;

  @override
  void initState() {
    super.initState();
    final CompanySubscription sub =
        CompanySubscription.fromCompany(widget.company);
    if (sub.plan != null) {
      _plan = sub.plan!;
    }
    if (sub.billingCycle != null) {
      _cycle = sub.billingCycle!;
    }
  }

  // ---------------------------------------------------------------------------
  // Date computation
  // ---------------------------------------------------------------------------

  DateTime _startFrom() {
    final CompanySubscription sub =
        CompanySubscription.fromCompany(widget.company);
    final DateTime now = DateTime.now().toUtc();
    final DateTime? until = sub.subscribedUntil;
    if (sub.isActive && until != null && until.isAfter(now)) {
      return until;
    }
    return now;
  }

  DateTime _newExpiry() {
    final Duration d = _cycle == BillingCycle.yearly
        ? const Duration(days: 365)
        : const Duration(days: 30);
    return _startFrom().add(d);
  }

  int _price() => PlanLimits.price(_plan, _cycle);

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  void _confirmActivate() {
    Navigator.of(context).pop(
      AdminSubscriptionChoice(
        action: AdminSubscriptionAction.activateOrExtend,
        planId: _plan == SubscriptionPlan.pro ? 'pro' : 'basic',
        billingCycle: _cycle == BillingCycle.yearly ? 'yearly' : 'monthly',
      ),
    );
  }

  void _confirmCancel() {
    Navigator.of(context).pop(
      const AdminSubscriptionChoice(
        action: AdminSubscriptionAction.cancel,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CompanySubscription sub =
        CompanySubscription.fromCompany(widget.company);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.company.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            _statusLabel(sub),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 4),

              // ---- Plan ----
              Text(
                'الباقة',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<SubscriptionPlan>(
                segments: const <ButtonSegment<SubscriptionPlan>>[
                  ButtonSegment<SubscriptionPlan>(
                    value: SubscriptionPlan.basic,
                    label: Text('الأساسية'),
                  ),
                  ButtonSegment<SubscriptionPlan>(
                    value: SubscriptionPlan.pro,
                    label: Text('برو'),
                  ),
                ],
                selected: <SubscriptionPlan>{_plan},
                onSelectionChanged: (Set<SubscriptionPlan> s) {
                  setState(() => _plan = s.first);
                },
              ),

              const SizedBox(height: 14),

              // ---- Cycle ----
              Text(
                'الدورة',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<BillingCycle>(
                segments: const <ButtonSegment<BillingCycle>>[
                  ButtonSegment<BillingCycle>(
                    value: BillingCycle.monthly,
                    label: Text('شهري'),
                  ),
                  ButtonSegment<BillingCycle>(
                    value: BillingCycle.yearly,
                    label: Text('سنوي'),
                  ),
                ],
                selected: <BillingCycle>{_cycle},
                onSelectionChanged: (Set<BillingCycle> s) {
                  setState(() => _cycle = s.first);
                },
              ),

              const SizedBox(height: 16),

              // ---- Preview ----
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _PreviewRow(
                        label: 'الباقة المختارة',
                        value: '${_plan.label} — ${_cycle.label}',
                      ),
                      _PreviewRow(
                        label: 'السعر',
                        value: '${_price()} ج.م',
                      ),
                      _PreviewRow(
                        label: 'تبدأ من',
                        value: _date.format(_startFrom().toLocal()),
                      ),
                      _PreviewRow(
                        label: 'تنتهي في',
                        value: _date.format(_newExpiry().toLocal()),
                        emphasize: true,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // ---- Cancel ----
              TextButton.icon(
                icon: const Icon(Icons.block_outlined, size: 18),
                label: const Text('إنهاء الاشتراك'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  minimumSize: const Size.fromHeight(40),
                ),
                onPressed: _confirmCancel,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
                child: Text(
                  'سيصبح حساب الشركة في وضع القراءة فقط حتى تجديده.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: Text(_activateLabel(sub)),
          onPressed: _confirmActivate,
        ),
      ],
    );
  }

  static String _activateLabel(CompanySubscription sub) {
    if (sub.isActive) return 'تمديد';
    return 'تفعيل';
  }

  static String _statusLabel(CompanySubscription sub) {
    final String planLabel = sub.plan?.label ?? '—';
    final int? days = sub.daysRemaining;
    if (sub.isExpired) {
      return 'الحالة: منتهي — جدّد لاستعادة كامل الميزات';
    }
    if (sub.isTrial) {
      return days == null
          ? 'الحالة: تجربة مجانية'
          : 'الحالة: تجربة — $days يوم متبقٍ';
    }
    if (days == null) {
      return 'الحالة: نشط — باقة $planLabel';
    }
    return 'الحالة: نشط — باقة $planLabel · $days يوم متبقٍ';
  }
}

// ============================================================================
// Preview row
// ============================================================================

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              color: emphasize ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
