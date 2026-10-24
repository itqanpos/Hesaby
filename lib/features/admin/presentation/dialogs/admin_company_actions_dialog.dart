// lib/features/admin/presentation/dialogs/admin_company_actions_dialog.dart

import 'package:flutter/material.dart';

import '../../../companies/domain/entities/company.dart';
import '../../../companies/domain/entities/company_subscription.dart';

// ============================================================================
// Public API
// ============================================================================

enum AdminSubscriptionAction { renew, suspend, unsuspend, cancel, viewPayments }

/// نتيجة الحوار — ما يستهلكه `admin_companies_tab.dart`.
class AdminSubscriptionChoice {
  const AdminSubscriptionChoice({
    required this.action,
    this.planId,
    this.billingCycle,
    this.reason,
  });

  final AdminSubscriptionAction action;
  final String? planId;
  final String? billingCycle; // 'monthly' | 'yearly' | 'lifetime'
  final String? reason;       // إلزامي عند suspend

  @override
  String toString() => 'AdminSubscriptionChoice('
      'action: $action, plan: $planId, cycle: $billingCycle)';
}

/// خيارات دورة الفوترة — مطابقة لـ منطق SQL في admin_update_subscription().
const List<({String value, String label})> kBillingCycleOptions =
    <({String value, String label})>[
  (value: 'monthly', label: 'شهري (30 يومًا)'),
  (value: 'yearly', label: 'سنوي (365 يومًا)'),
  (value: 'lifetime', label: 'مدى الحياة'),
];

Future<AdminSubscriptionChoice?> showAdminCompanyActionsDialog({
  required BuildContext context,
  required Company company,
}) {
  return showDialog<AdminSubscriptionChoice>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AdminCompanyActionsDialog(company: company),
  );
}

// ============================================================================
// Dialog
// ============================================================================

enum _Phase { choose, suspension, renew, cancelConfirm }

class _AdminCompanyActionsDialog extends StatefulWidget {
  const _AdminCompanyActionsDialog({required this.company});
  final Company company;

  @override
  State<_AdminCompanyActionsDialog> createState() =>
      _AdminCompanyActionsDialogState();
}

class _AdminCompanyActionsDialogState
    extends State<_AdminCompanyActionsDialog> {
  _Phase _phase = _Phase.choose;

  final TextEditingController _reasonCtrl = TextEditingController();
  final TextEditingController _planCtrl = TextEditingController();
  String _billingCycle = 'monthly';
  String? _error;

  @override
  void initState() {
    super.initState();
    _planCtrl.text = widget.company.planId ?? '';
    _billingCycle = widget.company.billingCycle == 'yearly' ||
            widget.company.billingCycle == 'lifetime'
        ? widget.company.billingCycle!
        : 'monthly';
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _planCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  void _backToChoose() {
    setState(() {
      _phase = _Phase.choose;
      _error = null;
    });
  }

  void _cancelDialog() => Navigator.of(context).pop();

  void _emit(AdminSubscriptionChoice choice) =>
      Navigator.of(context).pop(choice);

  // ---------------------------------------------------------------------------
  // Action handling
  // ---------------------------------------------------------------------------

  void _onActionTap(AdminSubscriptionAction action) {
    switch (action) {
      case AdminSubscriptionAction.viewPayments:
      case AdminSubscriptionAction.unsuspend:
        _emit(AdminSubscriptionChoice(action: action));

      case AdminSubscriptionAction.suspend:
        setState(() {
          _phase = _Phase.suspension;
          _error = null;
        });

      case AdminSubscriptionAction.renew:
        setState(() {
          _phase = _Phase.renew;
          _error = null;
        });

      case AdminSubscriptionAction.cancel:
        setState(() {
          _phase = _Phase.cancelConfirm;
          _error = null;
        });
    }
  }

  void _submitSuspension() {
    final String reason = _reasonCtrl.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'اكتب سبب الإيقاف (5 أحرف على الأقل).');
      return;
    }
    _emit(AdminSubscriptionChoice(
      action: AdminSubscriptionAction.suspend,
      reason: reason,
    ));
  }

  void _submitRenew() {
    final String plan = _planCtrl.text.trim();
    if (plan.isEmpty) {
      setState(() => _error = 'اسم الخطة مطلوب.');
      return;
    }
    _emit(AdminSubscriptionChoice(
      action: AdminSubscriptionAction.renew,
      planId: plan,
      billingCycle: _billingCycle,
    ));
  }

  void _submitCancel() {
    _emit(const AdminSubscriptionChoice(
      action: AdminSubscriptionAction.cancel,
    ));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _DialogTitle(
        company: widget.company,
        onBack: _phase == _Phase.choose ? null : _backToChoose,
        phase: _phase,
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (_phase) {
              _Phase.choose => _ChooseView(
                  key: const ValueKey<String>('choose'),
                  company: widget.company,
                  onAction: _onActionTap,
                ),
              _Phase.suspension => _SuspensionView(
                  key: const ValueKey<String>('suspension'),
                  controller: _reasonCtrl,
                  error: _error,
                  onErrorDismiss: () => setState(() => _error = null),
                ),
              _Phase.renew => _RenewView(
                  key: const ValueKey<String>('renew'),
                  planController: _planCtrl,
                  billingCycle: _billingCycle,
                  onBillingCycleChanged: (String v) =>
                      setState(() => _billingCycle = v),
                  error: _error,
                  isCurrentLifetime:
                      widget.company.billingCycle == 'lifetime',
                ),
              _Phase.cancelConfirm => _CancelConfirmView(
                  key: const ValueKey<String>('cancel'),
                  company: widget.company,
                ),
            },
          ),
        ),
      ),
      actions: _buildActions(context),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_phase) {
      case _Phase.choose:
        return <Widget>[
          TextButton(
            onPressed: _cancelDialog,
            child: const Text('إغلاق'),
          ),
        ];

      case _Phase.suspension:
        return <Widget>[
          TextButton(onPressed: _backToChoose, child: const Text('رجوع')),
          FilledButton.icon(
            onPressed: _submitSuspension,
            icon: const Icon(Icons.block),
            label: const Text('تأكيد الإيقاف'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
        ];

      case _Phase.renew:
        return <Widget>[
          TextButton(onPressed: _backToChoose, child: const Text('رجوع')),
          FilledButton.icon(
            onPressed: _submitRenew,
            icon: const Icon(Icons.autorenew),
            label: const Text('تجديد الاشتراك'),
          ),
        ];

      case _Phase.cancelConfirm:
        return <Widget>[
          TextButton(onPressed: _backToChoose, child: const Text('رجوع')),
          FilledButton.icon(
            onPressed: _submitCancel,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('تأكيد الإلغاء'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
        ];
    }
  }
}

// ============================================================================
// Title (with back + current status)
// ============================================================================

class _DialogTitle extends StatelessWidget {
  const _DialogTitle({
    required this.company,
    required this.onBack,
    required this.phase,
  });

  final Company company;
  final VoidCallback? onBack;
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final String title = switch (phase) {
      _Phase.choose => 'إدارة الشركة',
      _Phase.suspension => 'إيقاف الشركة',
      _Phase.renew => 'تجديد الاشتراك',
      _Phase.cancelConfirm => 'إلغاء الاشتراك',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (onBack != null)
              IconButton(
                tooltip: 'رجوع',
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              )
            else
              const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.storefront_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  company.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusBadge(company: company),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.company});
  final Company company;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ({String label, Color bg, Color fg}) v = _resolve(company, scheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: v.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        v.label,
        style: TextStyle(
          color: v.fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static ({String label, Color bg, Color fg}) _resolve(
    Company c,
    ColorScheme scheme,
  ) {
    if (c.isSuspended) {
      return (label: 'محظور', bg: scheme.error, fg: scheme.onError);
    }
    if (c.billingCycle == 'lifetime') {
      return (
        label: 'مدى الحياة',
        bg: const Color(0xFFE1BEE7),
        fg: const Color(0xFF6A1B9A),
      );
    }
    final CompanySubscription sub = CompanySubscription.fromCompany(c);
    if (sub.isExpired) {
      return (
        label: 'منتهي',
        bg: scheme.errorContainer,
        fg: scheme.onErrorContainer,
      );
    }
    if (sub.isTrial) {
      final int? d = sub.daysRemaining;
      return (
        label: d == null ? 'تجربة' : 'تجربة · $d يوم',
        bg: const Color(0xFFFFECB3),
        fg: const Color(0xFF8D6E00),
      );
    }
    final int? d = sub.daysRemaining;
    return (
      label: d == null ? 'نشط' : 'نشط · $d يوم',
      bg: const Color(0xFFC8E6C9),
      fg: const Color(0xFF1B5E20),
    );
  }
}

// ============================================================================
// Choose view — قائمة الإجراءات المتاحة
// ============================================================================

class _ChooseView extends StatelessWidget {
  const _ChooseView({
    super.key,
    required this.company,
    required this.onAction,
  });

  final Company company;
  final ValueChanged<AdminSubscriptionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final bool suspended = company.isSuspended;
    final CompanySubscription sub = CompanySubscription.fromCompany(company);

    final List<Widget> tiles = <Widget>[
      _ActionTile(
        icon: Icons.receipt_long_outlined,
        title: 'عرض المدفوعات',
        subtitle: 'سجل الفواتير والمدفوعات السابقة',
        onTap: () => onAction(AdminSubscriptionAction.viewPayments),
      ),
      if (!suspended)
        _ActionTile(
          icon: Icons.autorenew,
          title: 'تجديد الاشتراك',
          subtitle: 'شهري، سنوي، أو مدى الحياة',
          accent: Theme.of(context).colorScheme.primary,
          onTap: () => onAction(AdminSubscriptionAction.renew),
        ),
      if (suspended)
        _ActionTile(
          icon: Icons.lock_open_outlined,
          title: 'رفع الحظر',
          subtitle: 'إعادة تفعيل وصول المستخدمين',
          accent: const Color(0xFF1B5E20),
          onTap: () => onAction(AdminSubscriptionAction.unsuspend),
        ),
      if (!suspended)
        _ActionTile(
          icon: Icons.block,
          title: 'حظر الشركة',
          subtitle: 'منع الوصول مؤقتًا — يتطلب سببًا',
          accent: Theme.of(context).colorScheme.error,
          onTap: () => onAction(AdminSubscriptionAction.suspend),
        ),
      if (!suspended && sub.isActive)
        _ActionTile(
          icon: Icons.cancel_outlined,
          title: 'إلغاء الاشتراك',
          subtitle: 'إيقاف الاشتراك نهائيًا بدون استرداد',
          accent: Theme.of(context).colorScheme.error,
          onTap: () => onAction(AdminSubscriptionAction.cancel),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < tiles.length; i++) ...<Widget>[
          tiles[i],
          if (i != tiles.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color color = accent ?? scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_left, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Suspension view — سبب الإيقاف (إلزامي)
// ============================================================================

class _SuspensionView extends StatelessWidget {
  const _SuspensionView({
    super.key,
    required this.controller,
    required this.error,
    required this.onErrorDismiss,
  });

  final TextEditingController controller;
  final String? error;
  final VoidCallback onErrorDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.warning_amber, color: scheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'سيتم منع جميع مستخدمي الشركة من الوصول فورًا. '
                  'سيبقى السبب مرئيًا في سجل التدقيق.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          onChanged: (_) {
            if (error != null) onErrorDismiss();
          },
          decoration: InputDecoration(
            labelText: 'سبب الإيقاف',
            hintText: 'مثال: عدم سداد مستحقات — مخالفة شروط الاستخدام',
            border: const OutlineInputBorder(),
            errorText: error,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Renew view — دورة الفوترة + الخطة
// ============================================================================

class _RenewView extends StatelessWidget {
  const _RenewView({
    super.key,
    required this.planController,
    required this.billingCycle,
    required this.onBillingCycleChanged,
    required this.error,
    required this.isCurrentLifetime,
  });

  final TextEditingController planController;
  final String billingCycle;
  final ValueChanged<String> onBillingCycleChanged;
  final String? error;
  final bool isCurrentLifetime;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isLifetime = billingCycle == 'lifetime';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'دورة الفوترة',
          style: theme.textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        RadioGroup<String>(
          groupValue: billingCycle,
          onChanged: (String? v) {
            if (v != null) onBillingCycleChanged(v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final ({String value, String label}) opt
                  in kBillingCycleOptions)
                RadioListTile<String>(
                  value: opt.value,
                  title: Text(opt.label),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        if (isLifetime) ...<Widget>[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.info_outline,
                    color: scheme.onPrimaryContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'سيتم تجاهل تاريخ الانتهاء نهائيًا (الترخيص مدى الحياة).',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (isCurrentLifetime && !isLifetime) ...<Widget>[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.warning_amber, color: scheme.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تحويل ترخيص مدى الحياة إلى مؤقت — لا رجعة فيه.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: planController,
          decoration: InputDecoration(
            labelText: 'اسم الخطة (plan_id)',
            hintText: 'مثال: basic, pro, enterprise',
            border: const OutlineInputBorder(),
            errorText: error,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Cancel confirm view
// ============================================================================

class _CancelConfirmView extends StatelessWidget {
  const _CancelConfirmView({super.key, required this.company});

  final Company company;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber, color: scheme.error),
              const SizedBox(width: 8),
              Text(
                'تأكيد إلغاء الاشتراك',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'سيتم تحويل حالة اشتراك "${company.name}" إلى "ملغى". '
            'لن يتمكن المستخدمون من الوصول للخدمات المدفوعة. '
            'هذا الإجراء يُسجَّل في سجل التدقيق.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
