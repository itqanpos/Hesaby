// lib/l10n/app_localizations_ar.dart
import 'app_localizations.dart';

/// Arabic strings — the primary language of HESABI.
class AppLocalizationsAr extends AppLocalizations {
  const AppLocalizationsAr();

  @override
  String get appName => 'حسابي';

  @override
  String get appTagline =>
      'نظام متكامل لإدارة نقاط البيع والمخزون والمبيعات والمحاسبة';

  @override
  String get homeTitle => 'مرحبًا بك في حسابي';

  @override
  String get homeSubtitle =>
      'هذه نسخة الأساس (المرحلة صفر) للتحقق من عمل البنية التحتية للمشروع.';

  @override
  String get homePhaseLabel => 'المرحلة 0 — الأساس';

  @override
  String get homeFoundationStatusTitle => 'حالة البنية التحتية';

  @override
  String get homeStatusFlutter => 'إطار Flutter';

  @override
  String get homeStatusRouting => 'نظام التوجيه';

  @override
  String get homeStatusTheme => 'السمة والتنسيق';

  @override
  String get homeStatusLocalization => 'التعريب والترجمة';

  @override
  String get homeStatusResponsive => 'التصميم المتجاوب';

  @override
  String get homeStatusSupabase => 'الاتصال بـ Supabase';

  @override
  String get homeStatusReady => 'جاهز';

  @override
  String get homeStatusPending => 'غير مهيأ';

  @override
  String get homeEnvironmentLabel => 'بيئة التشغيل';

  @override
  String get homeEnvironmentDevelopment => 'تطوير';

  @override
  String get homeEnvironmentStaging => 'اختبار';

  @override
  String get homeEnvironmentProduction => 'إنتاج';

  @override
  String get errorTitle => 'حدث خطأ';

  @override
  String get errorRouteNotFound => 'الصفحة المطلوبة غير موجودة.';

  @override
  String get actionGoHome => 'العودة للرئيسية';
}
