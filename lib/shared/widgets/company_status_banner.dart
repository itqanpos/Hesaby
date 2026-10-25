// lib/shared/widgets/company_status_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/presentation/providers/platform_admin_provider.dart';
import '../../features/companies/presentation/providers/company_status_provider.dart';

/// شريط يظهر أعلى الشاشة عندما تكون الشركة موقوفة أو اشتراكها منتهي.
///
/// **السلوك:**
/// * لا يظهر إذا كانت الشركة نشطة.
/// * لا يظهر لأدمن المنصة (لأنه يحتاج رؤية كل شيء).
/// * يعرض سبب الإيقاف إن وُجد.
/// * في الحالتين (موقوفة أو منتهية) يخبر المستخدم أن العمليات معطلة.
class CompanyStatusBanner extends ConsumerWidget {
  const CompanyStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isPlatformAdmin = ref.watch(isPlatformAdminProvider);
    if (isPlatformAdmin) return const SizedBox.shrink();

    final CompanyStatusInfo info = ref.watch(companyStatusProvider);
    if (info.status == CompanyStatus.active) {
      return const SizedBox.shrink();
    }

    final bool suspended = info.status == CompanyStatus.suspended;
    final Color bg =
        suspended ? const Color(0xFFC62828) : const Color(0xFFEF6C00);
    final IconData icon =
        suspended ? Icons.block : Icons.hourglass_bottom;
    final String title =
        suspended ? 'الحساب موقوف' : 'انتهت صلاحية الاشتراك';
    final String message = info.reason?.isNotEmpty == true
        ? info.reason!
        : 'تواصل مع إدارة المنصة لإعادة التفعيل.';

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$message — جميع العمليات الجديدة (بيع، شراء، تعديل) معطلة.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                      height: 1.4,
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
}
