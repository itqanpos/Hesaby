// lib/features/settings/presentation/pages/settings_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/preferences/app_preferences_providers.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../companies/presentation/providers/members_providers.dart';

/// Application settings page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final Locale? locale = ref.watch(localeProvider).valueOrNull;
    final bool canManageMembers = ref.watch(isManagerProvider);

    return AppShell(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: <Widget>[
          // ---- الحساب ----
          const _SectionHeader(title: 'الحساب'),
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'الملف الشخصي',
            subtitle: 'الاسم، الهاتف، كلمة المرور',
            onTap: () => context.pushNamed(AppRouter.profileName),
          ),

          const SizedBox(height: 8),

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
          if (canManageMembers)
            _SettingsTile(
              icon: Icons.groups_outlined,
              title: 'الأعضاء والصلاحيات',
              subtitle: 'إدارة الفريق وتحديد صلاحيات كل عضو',
              onTap: () => context.pushNamed(AppRouter.membersName),
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
            subtitle: 'اختيار طابعة حرارية للطباعة المباشرة',
            onTap: () => context.pushNamed(AppRouter.printerSettingsName),
          ),

          const SizedBox(height: 8),

          // ---- الجلسة ----
          const _SectionHeader(title: 'الجلسة'),
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
          ),
          _PickerOption<ThemeMode>(
            value: ThemeMode.light,
            label: 'فاتح',
            subtitle: 'خلفية بيضاء دائمًا',
            icon: Icons.light_mode_outlined,
          ),
          _PickerOption<ThemeMode>(
            value: ThemeMode.dark,
            label: 'داكن',
            subtitle: 'خلفية داكنة دائمًا',
            icon: Icons.dark_mode_outlined,
          ),
        ],
        current: current,
      ),
    );
    if (picked == null) return;
    await ref.read(themeModeProvider.notifier).setThemeMode(picked);
  }

  static String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'فاتح';
      case ThemeMode.dark:
        return 'داكن';
      case ThemeMode.system:
        return 'تلقائي';
    }
  }

  // ---------------------------------------------------------------------------
  // Locale
  // ---------------------------------------------------------------------------

  Future<void> _pickLocale(
    BuildContext context,
    WidgetRef ref,
    Locale? current,
  ) async {
    final _LocaleChoice? picked =
        await showModalBottomSheet<_LocaleChoice>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext ctx) => _PickerSheet<_LocaleChoice>(
        title: 'لغة التطبيق',
        options: const <_PickerOption<_LocaleChoice>>[
          _PickerOption<_LocaleChoice>(
            value: _LocaleChoice.system,
            label: 'تلقائي',
            subtitle: 'يتبع لغة النظام',
            icon: Icons.settings_suggest_outlined,
          ),
          _PickerOption<_LocaleChoice>(
            value: _LocaleChoice.ar,
            label: 'العربية',
            subtitle: 'الواجهة بالعربية',
            icon: Icons.translate,
          ),
          _PickerOption<_LocaleChoice>(
            value: _LocaleChoice.en,
            label: 'English',
            subtitle: 'English interface',
            icon: Icons.translate,
          ),
        ],
        current: _currentLocaleChoice(current),
      ),
    );
    if (picked == null) return;

    final Locale? newLocale = switch (picked) {
      _LocaleChoice.system => null,
      _LocaleChoice.ar => const Locale('ar'),
      _LocaleChoice.en => const Locale('en'),
    };
    await ref.read(localeProvider.notifier).setLocale(newLocale);
  }

  static _LocaleChoice _currentLocaleChoice(Locale? locale) {
    if (locale == null) return _LocaleChoice.system;
    if (locale.languageCode == 'en') return _LocaleChoice.en;
    return _LocaleChoice.ar;
  }

  static String _localeLabel(Locale? locale) {
    if (locale == null) return 'تلقائي (لغة النظام)';
    if (locale.languageCode == 'en') return 'English';
    return 'العربية';
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text(
          'هل تريد تسجيل الخروج من هذا الجهاز؟',
        ),
        actions: <Widget>[
          AppButton(
            label: 'إلغاء',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'تسجيل الخروج',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await ref.read(authProvider.notifier).logout();
  }
}

// ============================================================================
// Section header
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Settings tile
// ============================================================================

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.enabled = true,
    this.isDestructive = false,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isDestructive;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color iconColor = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
        : isDestructive
            ? scheme.error
            : scheme.primary;

    final Color titleColor = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.65)
        : isDestructive
            ? scheme.error
            : scheme.onSurface;

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (badge != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                child: Text(
                  badge!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else if (enabled)
            Icon(
              Icons.chevron_left,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    final Widget decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: enabled && onTap != null
          ? InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: content,
            )
          : content,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Opacity(opacity: enabled ? 1.0 : 0.85, child: decorated),
    );
  }
}

// ============================================================================
// Picker sheet
// ============================================================================

enum _LocaleChoice { system, ar, en }

class _PickerOption<T> {
  const _PickerOption({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  final T value;
  final String label;
  final String subtitle;
  final IconData icon;
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.current,
  });

  final String title;
  final List<_PickerOption<T>> options;
  final T current;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final _PickerOption<T> option in options)
              _OptionTile<T>(
                option: option,
                selected: option.value == current,
                onTap: () => Navigator.of(context).pop(option.value),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            const SizedBox(height: 4),
            Text(
              'التغيير يُحفظ فورًا على هذا الجهاز',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile<T> extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _PickerOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  option.icon,
                  color: selected ? scheme.primary : scheme.onSurface,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        option.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    color: scheme.primary,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
