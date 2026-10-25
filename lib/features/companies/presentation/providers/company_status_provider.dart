// lib/features/companies/presentation/providers/company_status_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/company.dart';
import 'company_context_provider.dart';

/// حالة الشركة النشطة حالياً في التطبيق.
enum CompanyStatus {
  /// الشركة نشطة، اشتراكها ساري، وكل العمليات مسموحة.
  active,

  /// الشركة نشطة لكن اشتراكها انتهى (فترة قراءة فقط).
  expired,

  /// الشركة موقوفة إدارياً من لوحة تحكم المنصة.
  suspended,
}

/// تفاصيل حالة الشركة (الحالة + سبب الإيقاف إن وُجد).
class CompanyStatusInfo {
  const CompanyStatusInfo({
    required this.status,
    this.reason,
  });

  final CompanyStatus status;
  final String? reason;

  bool get canWrite => status == CompanyStatus.active;
  bool get isSuspended => status == CompanyStatus.suspended;
  bool get isExpired => status == CompanyStatus.expired;
}

/// يقرأ حالة الشركة الحالية ويحسب ما إذا كانت الكتابة مسموحة.
///
/// **قواعد الحساب:**
/// 1. إذا `company.isActive == false` → **موقوفة**.
/// 2. إذا `company.isSuspended == true` → **موقوفة**.
/// 3. إذا `subscribedUntil` في الماضي → **منتهية**.
/// 4. إذا `subscriptionStatus == 'expired'` → **منتهية**.
/// 5. وإلا → **نشطة**.
///
/// لا يفرق بين "موقوفة إدارياً" و"منتهية" في منع الكتابة،
/// لكنه يفرق في الرسائل المعروضة للمستخدم.
final companyStatusProvider = Provider<CompanyStatusInfo>((ref) {
  final Company? company = ref.watch(
    companyContextProvider.select((s) => s.currentCompany),
  );

  if (company == null) {
    // لا توجد شركة مختارة بعد (أثناء التحميل) → نعتبرها نشطة مؤقتاً
    // لتجنب ظهور البانر أثناء التحميل.
    return const CompanyStatusInfo(status: CompanyStatus.active);
  }

  // 1. الإيقاف الإداري
  if (!company.isActive || company.isSuspended) {
    return CompanyStatusInfo(
      status: CompanyStatus.suspended,
      reason: company.suspensionReason,
    );
  }

  // 2. انتهاء الاشتراك
  final DateTime? end = company.subscribedUntil;
  if (end != null && end.isBefore(DateTime.now())) {
    return CompanyStatusInfo(
      status: CompanyStatus.expired,
      reason: 'انتهت صلاحية الاشتراك',
    );
  }

  if (company.subscriptionStatus.toLowerCase() == 'expired') {
    return const CompanyStatusInfo(
      status: CompanyStatus.expired,
      reason: 'انتهت صلاحية الاشتراك',
    );
  }

  // 3. نشطة
  return const CompanyStatusInfo(status: CompanyStatus.active);
});

/// مزود مبسط يجيب على سؤال واحد: "هل يمكن لهذه الشركة إجراء عمليات كتابة؟"
final companyCanWriteProvider = Provider<bool>((ref) {
  return ref.watch(companyStatusProvider).canWrite;
});
