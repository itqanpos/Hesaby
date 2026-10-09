// lib/features/companies/presentation/widgets/subscription_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../domain/entities/company_subscription.dart';
import '../providers/subscription_providers.dart';

/// Top-of-screen reminder banner for trial / expiring / expired accounts.
///
/// * **Trial (any day left)** → yellow "تجربة مجانية — X يوم متبقي".
/// * **Trial with ≤ 3 days**  → deeper orange "تجربتك تنتهي قريبًا".
/// * **Active with ≤ 7 days** → yellow "اشتراكك ينتهي بعد X يوم".
/// * **Expired / Cancelled**  → red "انتهى اشتراكك — جدّد الآن".
/// * **Healthy active**       → hidden (returns [SizedBox.shrink]).
///
/// Tapping always navigates to `/subscription`.
class SubscriptionBanner extends ConsumerWidget {
  const SubscriptionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CompanySubscription? sub = ref.watch(subscriptionProvider);
    if (sub == null) return const SizedBox.shrink();

    // Healthy active accounts see nothing.
    if (sub.isActive && !sub.isExpiringSoon) {
      return const SizedBox.shrink();
    }

    final _BannerStyle style = _resolveStyle(sub);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: style.background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.pushNamed(AppRouter.subscriptionName),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(style.icon, color: style.foreground, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        style.title,
                        style: TextStyle(
                          color: style.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.2,
                        ),
                      ),
                      if (style.subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          style.subtitle!,
                          style: TextStyle(
                            color: style.foreground.withValues(alpha: 0.85),
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  style.actionLabel,
                  style: TextStyle(
                    color: style.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_left, color: style.foreground, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static _BannerStyle _resolveStyle(CompanySubscription sub) {
    // Expired / cancelled → red.
    if (sub.isExpired) {
      return const _BannerStyle(
        background: Color(0xFFFFEBEE),
        foreground: Color(0xFFB71C1C),
        icon: Icons.error_outline,
        title: 'انتهى اشتراكك — الحساب للقراءة فقط',
        subtitle: 'جدّد الآن لاستعادة كل الميزات',
        actionLabel: 'تجديد',
      );
    }

    // Trial paths.
    if (sub.isTrial) {
      final int? days = sub.daysRemaining;
      if (days != null && days <= 3) {
        return _BannerStyle(
          background: const Color(0xFFFFE0B2),
          foreground: const Color(0xFFE65100),
          icon: Icons.hourglass_bottom_outlined,
          title: days == 0
              ? 'تجربتك تنتهي اليوم'
              : 'تجربتك تنتهي بعد $days ${days == 1 ? "يوم" : "أيام"}',
          subtitle: 'ارفع باقتك لتفادي التوقف',
          actionLabel: 'ترقية',
        );
      }
      return _BannerStyle(
        background: const Color(0xFFFFF8E1),
        foreground: const Color(0xFF8D6E00),
        icon: Icons.card_giftcard_outlined,
        title: days == null
            ? 'أنت في الفترة التجريبية'
            : 'تجربة مجانية — $days ${days == 1 ? "يوم" : "أيام"} متبقية',
        subtitle: 'اختر باقتك قبل انتهاء التجربة',
        actionLabel: 'ترقية',
      );
    }

    // Active but expiring soon (≤ 3 days, isExpiringSoon uses ≤ 3).
    final int? days = sub.daysRemaining;
    return _BannerStyle(
      background: const Color(0xFFFFF8E1),
      foreground: const Color(0xFF8D6E00),
      icon: Icons.event_available_outlined,
      title: days == null
          ? 'اشتراكك يقترب من الانتهاء'
          : 'اشتراكك ينتهي بعد $days ${days == 1 ? "يوم" : "أيام"}',
      subtitle: 'جدّد الآن لتجنب التوقف',
      actionLabel: 'تجديد',
    );
  }
}

class _BannerStyle {
  const _BannerStyle({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.title,
    required this.actionLabel,
    this.subtitle,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
}
