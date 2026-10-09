// lib/features/companies/presentation/pages/subscription_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/layouts/app_shell.dart';
import '../../domain/entities/company_subscription.dart';
import '../../domain/entities/plan_limits.dart';
import '../providers/company_context_provider.dart';
import '../providers/company_context_state.dart';
import '../providers/subscription_providers.dart';

/// Subscription page.
///
/// Shows the current state, the available plans, and the way to activate
/// or renew the subscription by contacting the support channel.
///
/// **Activation flow (Phase T-1 final):**
/// 1. User picks a plan.
/// 2. Taps the WhatsApp button — a prefilled message opens in WhatsApp.
/// 3. Support confirms and activates the account from the platform side.
///
/// No payment gateway is involved; the app only provides a fast, prefilled
/// channel to reach support.
class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  /// Support phone in E.164 format (international — no leading 0).
  /// Local display uses the Egyptian format (with leading 0).
  static const String _supportPhoneE164 = '201019936233';
  static const String _supportPhoneLocal = '01019936233';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanySubscription? sub = ref.watch(subscriptionProvider);

    return AppShell(
      appBar: AppBar(
        title: const Text('الاشتراك'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        children: <Widget>[
          _CurrentStatusCard(subscription: sub),
          const SizedBox(height: 20),
          const _SectionTitle(
            title: 'الباقات المتاحة',
            icon: Icons.workspace_premium_outlined,
          ),
          const SizedBox(height: 10),
          for (final PlanDescription plan in PlanDescription.all) ...<Widget>[
            _PlanCard(plan: plan),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
          const _SectionTitle(
            title: 'تفعيل الاشتراك',
            icon: Icons.support_agent_outlined,
          ),
          const SizedBox(height: 10),
          const _SupportSection(
            phoneE164: _supportPhoneE164,
            phoneLocal: _supportPhoneLocal,
          ),
          const SizedBox(height: 20),
          const _HowItWorksCard(),
        ],
      ),
    );
  }
}

// ============================================================================
// Current status card
// ============================================================================

class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({required this.subscription});

  final CompanySubscription? subscription;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (subscription == null) {
      return const SizedBox.shrink();
    }

    final CompanySubscription sub = subscription!;
    final _StatusVisual visual = _visualFor(sub, scheme);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: visual.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: visual.iconBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(visual.icon, color: visual.foreground, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    visual.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: visual.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    visual.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: visual.foreground.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static _StatusVisual _visualFor(
    CompanySubscription sub,
    ColorScheme scheme,
  ) {
    if (sub.isExpired) {
      return const _StatusVisual(
        background: Color(0xFFFFEBEE),
        border: Color(0xFFEF9A9A),
        iconBackground: Color(0xFFFFCDD2),
        foreground: Color(0xFFB71C1C),
        icon: Icons.error_outline,
        title: 'اشتراكك منتهي',
        subtitle: 'حسابك في وضع القراءة فقط — تواصل مع الدعم للتفعيل',
      );
    }

    if (sub.isTrial) {
      final int? days = sub.daysRemaining;
      return _StatusVisual(
        background: const Color(0xFFFFF8E1),
        border: const Color(0xFFFFE082),
        iconBackground: const Color(0xFFFFECB3),
        foreground: const Color(0xFF8D6E00),
        icon: Icons.card_giftcard_outlined,
        title: 'أنت في الفترة التجريبية',
        subtitle: days == null
            ? 'تواصل مع الدعم لتفعيل اشتراكك'
            : 'متبقٍ $days ${days == 1 ? "يوم" : "أيام"} — تواصل مع الدعم للتفعيل',
      );
    }

    // Active.
    final String planLabel = sub.plan?.label ?? '—';
    final int? days = sub.daysRemaining;
    return _StatusVisual(
      background: scheme.primaryContainer.withValues(alpha: 0.35),
      border: scheme.primary.withValues(alpha: 0.4),
      iconBackground: scheme.primary.withValues(alpha: 0.15),
      foreground: scheme.primary,
      icon: Icons.verified_outlined,
      title: 'اشتراكك نشط — باقة $planLabel',
      subtitle: days == null
          ? 'شكرًا لاشتراكك'
          : 'متبقٍ $days ${days == 1 ? "يوم" : "أيام"} على نهاية الفترة',
    );
  }
}

class _StatusVisual {
  const _StatusVisual({
    required this.background,
    required this.border,
    required this.iconBackground,
    required this.foreground,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Color background;
  final Color border;
  final Color iconBackground;
  final Color foreground;
  final IconData icon;
  final String title;
  final String subtitle;
}

// ============================================================================
// Section title
// ============================================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Plan card
// ============================================================================

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final PlanDescription plan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: plan.highlight
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.outlineVariant,
          width: plan.highlight ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            plan.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (plan.highlight) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'الأكثر اختيارًا',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.tagline,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PlanFeature(
              icon: Icons.group_outlined,
              label: '${plan.users} مستخدمين',
            ),
            _PlanFeature(
              icon: Icons.inventory_2_outlined,
              label: '${plan.products} منتج',
            ),
            _PlanFeature(
              icon: Icons.store_outlined,
              label: plan.branches == 1
                  ? 'فرع واحد'
                  : '${plan.branches} فروع',
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _PriceTag(
                    amount: plan.monthlyPrice,
                    unit: 'شهريًا',
                    highlight: plan.highlight,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PriceTag(
                    amount: plan.yearlyPrice,
                    unit: 'سنويًا',
                    highlight: plan.highlight,
                    badge: 'وفّر 2 شهر',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanFeature extends StatelessWidget {
  const _PlanFeature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  const _PriceTag({
    required this.amount,
    required this.unit,
    required this.highlight,
    this.badge,
  });

  final int amount;
  final String unit;
  final bool highlight;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  '$amount',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: highlight ? scheme.primary : scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  'ج.م',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              unit,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (badge != null) ...<Widget>[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Support section
// ============================================================================

class _SupportSection extends ConsumerWidget {
  const _SupportSection({
    required this.phoneE164,
    required this.phoneLocal,
  });

  final String phoneE164;
  final String phoneLocal;

  /// Opens the given URI in an external application, surfacing a SnackBar
  /// when the platform refuses to handle it (e.g. no WhatsApp installed
  /// and no browser — rare, but possible on locked-down devices).
  static Future<void> _open(
    BuildContext context,
    Uri uri,
  ) async {
    try {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح الرابط على هذا الجهاز')),
        );
      }
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الرابط على هذا الجهاز')),
      );
    }
  }

  /// Builds the prefilled WhatsApp message. Company name is included when
  /// available so support can act without a back-and-forth.
  Uri _whatsAppUri(WidgetRef ref) {
    final CompanyContextState ctx = ref.read(companyContextProvider);
    final String companyName = ctx.currentCompany?.name ?? '';
    final StringBuffer text = StringBuffer('مرحبًا الدعم الفني،');
    text.write(' أرغب في تفعيل اشتراك Hesaby.');
    if (companyName.isNotEmpty) {
      text.write(' اسم الشركة: $companyName.');
    }
    return Uri.parse(
      'https://wa.me/$phoneE164?text=${Uri.encodeComponent(text.toString())}',
    );
  }

  Uri get _phoneUri => Uri.parse('tel:+$phoneE164');

  Future<void> _copyNumber(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phoneLocal));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رقم الدعم الفني')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.headset_mic_outlined,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'الدعم الفني',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'تواصل لتفعيل أو تجديد الاشتراك',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Primary CTA: WhatsApp
            FilledButton.icon(
              icon: const Icon(Icons.chat_outlined, size: 20),
              label: const Text('تواصل عبر واتساب'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
              onPressed: () => _open(context, _whatsAppUri(ref)),
            ),
            const SizedBox(height: 8),

            // Secondary actions: call + copy.
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('اتصال'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => _open(context, _phoneUri),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('نسخ الرقم'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => _copyNumber(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Plain number, visible for those who prefer to save it.
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.phone_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'رقم الدعم الفني',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      phoneLocal,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// How-it-works card
// ============================================================================

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.help_outline,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'كيف يتم التفعيل؟',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _Step(
              number: '1',
              text: 'تواصل معنا عبر واتساب بالضغط على الزر أعلاه.',
            ),
            const _Step(
              number: '2',
              text: 'أخبرنا بالباقة التي تريدها (شهري أو سنوي).',
            ),
            const _Step(
              number: '3',
              text: 'سيتم تفعيل حسابك خلال دقائق بعد التأكيد.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
