// lib/features/settings/presentation/pages/settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/preferences/app_preferences_providers.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Application settings page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final Locale? locale = ref.watch(localeProvider).valueOrNull;

    return AppShell(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: <Widget>[
          // ---- الشركة ----
          const _SectionHeader(title: 'الشركة'),
          _SettingsTile(
            icon: Icons.business_outlined,
            title: 'بيانات الشركة',
            subtitle: 'الاسم، الهاتف، العنوان، العملة، المنطقة الزمنية',
            onTap: () => context.pushNamed(AppRouter.companyProfileName),
          ),
          _SettingsTile(
            icon: Icons.store_mall_directory_outlined,
            title: 'الفروع',
            subtitle: 'إضافة وتعديل فروع الشركة',
            onTap: () => context.pushNamed(AppRouter.branchesName),
          ),
          _SettingsTile(
            icon: Icons.tune_outlined,
            title: 'إعدادات الشركة',
            subtitle: 'الضريبة والخصم وقواعد البيع وتذييل الإيصال',
            onTap: () => context.pushNamed(AppRouter.companySettingsName),
          ),

          const SizedBox(height: 8),

          // ---- المظهر ----
          const _SectionHeader(title: 'المظهر'),
          _SettingsTile(
            icon: Icons.brightness_6_outlined,
            title: 'وضع المظهر',
            subtitle: _themeModeLabel(themeMode),
            onTap: () => _pickThemeMode(context, ref, themeMode),
          ),

          const SizedBox(height: 8),

          // ---- اللغة ----
          const _SectionHeader(title: 'اللغة'),
          _SettingsTile(
            icon: Icons.language_outlined,
            title: 'لغة التطبيق',
            subtitle: _localeLabel(locale),
            onTap: () => _pickLocale(context, ref, locale),
          ),

          const SizedBox(height: 8),

          // ---- الطابعة ----
          const _SectionHeader(title: 'الطابعة'),
          _SettingsTile(
            icon: Icons.print_outlined,
            title: 'إعدادات الطابعة',
            subtitle: 'البحث عن طابعة بلوتوث وربطها',
            enabled: false,
            badge: 'قريبًا',
            onTap: null,
          ),

          const SizedBox(height: 8),

          // ---- الحساب ----
          const _SectionHeader(title: 'الحساب'),
          _SettingsTile(
            icon: Icons.logout,
            title: 'تسجيل الخروج',
            subtitle: 'إنهاء الجلسة على هذا الجهاز',
            isDestructive: true,
            onTap: () => _confirmLogout(context, ref),
          ),

          const SizedBox(height: 8),

          // ---- حول التطبيق ----
          const _SectionHeader(title: 'حول التطبيق'),
          const _SettingsTile(
            icon: Icons.info_outline,
            title: 'الإصدار',
            subtitle: '0.1.0',
            enabled: false,
          ),
          const _SettingsTile(
            icon: Icons.code_outlined,
            title: 'المطوّر',
            subtitle: 'itqanpos',
            enabled: false,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Theme mode
  // ---------------------------------------------------------------------------

  Future<void> _pickThemeMode(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final ThemeMode? picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext ctx) => _PickerSheet<ThemeMode>(
        title: 'وضع المظهر',
        options: const <_PickerOption<ThemeMode>>[
          _PickerOption<ThemeMode>(
            value: ThemeMode.system,
            label: 'تلقائي',
            subtitle: 'يتبع إعدادات النظام',
            icon: Icons.brightness_auto_outlined,
         
