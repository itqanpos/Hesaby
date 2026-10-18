// lib/features/admin/presentation/pages/tabs/admin_app_control_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_loader.dart';
import '../../../../../shared/widgets/app_text_field.dart';
import '../../providers/admin_app_config_provider.dart';

class AdminAppControlTab extends ConsumerStatefulWidget {
  const AdminAppControlTab({super.key});

  @override
  ConsumerState<AdminAppControlTab> createState() => _AdminAppControlTabState();
}

class _AdminAppControlTabState extends ConsumerState<AdminAppControlTab> {
  // Local state for the form
  bool _initialized = false;
  bool _isSaving = false;

  bool _maintenanceMode = false;
  late TextEditingController _maintenanceMessageController;
  
  bool _announcementVisible = false;
  late TextEditingController _announcementTextController;
  String _announcementSeverity = 'info';

  // Feature flags (hardcoded for now)
  bool _flagPos = true;
  bool _flagReports = true;
  bool _flagPurchases = true;
  bool _flagInventory = true;

  @override
  void initState() {
    super.initState();
    _maintenanceMessageController = TextEditingController();
    _announcementTextController = TextEditingController();
  }

  @override
  void dispose() {
    _maintenanceMessageController.dispose();
    _announcementTextController.dispose();
    super.dispose();
  }

  void _hydrate(AppConfig config) {
    if (_initialized) return;
    _initialized = true;

    _maintenanceMode = config.maintenanceMode;
    _maintenanceMessageController.text = config.maintenanceMessage;
    
    _announcementVisible = config.announcementVisible;
    _announcementTextController.text = config.announcementText;
    _announcementSeverity = config.announcementSeverity;

    final flags = config.featureFlags;
    _flagPos = flags['pos'] as bool? ?? true;
    _flagReports = flags['reports'] as bool? ?? true;
    _flagPurchases = flags['purchases'] as bool? ?? true;
    _flagInventory = flags['inventory'] as bool? ?? true;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final newConfig = AppConfig(
      maintenanceMode: _maintenanceMode,
      maintenanceMessage: _maintenanceMessageController.text.trim(),
      announcementVisible: _announcementVisible,
      announcementText: _announcementTextController.text.trim(),
      announcementSeverity: _announcementSeverity,
      featureFlags: {
        'pos': _flagPos,
        'reports': _flagReports,
        'purchases': _flagPurchases,
        'inventory': _flagInventory,
      },
    );

    try {
      await ref.read(adminAppConfigProvider.notifier).save(newConfig);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات التطبيق بنجاح.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(adminAppConfigProvider);

    return configAsync.when(
      loading: () => const AppLoader(),
      error: (error, _) => Center(child: Text('خطأ في تحميل الإعدادات: $error')),
      data: (config) {
        _hydrate(config);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              // --- 1. Maintenance Mode ---
              _SectionCard(
                title: 'وضع الصيانة (Maintenance Mode)',
                icon: Icons.engineering_outlined,
                children: <Widget>[
                  SwitchListTile(
                    title: const Text('تفعيل وضع الصيانة'),
                    subtitle: const Text('إذا تم التفعيل، لن يتمكن المستخدمون العاديون من الدخول للتطبيق.'),
                    value: _maintenanceMode,
                    activeThumbColor: Colors.red, // ⬅️ تم استبدال activeColor
                    onChanged: _isSaving ? null : (v) => setState(() => _maintenanceMode = v),
                  ),
                  if (_maintenanceMode) ...<Widget>[
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: _maintenanceMessageController,
                      label: 'رسالة الصيانة',
                      hint: 'التطبيق تحت الصيانة. سنعود قريباً...',
                      maxLines: 2,
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 16),

              // --- 2. Announcements ---
              _SectionCard(
                title: 'الإعلانات العامة (Announcements)',
                icon: Icons.campaign_outlined,
                children: <Widget>[
                  SwitchListTile(
                    title: const Text('عرض شريط إعلان'),
                    subtitle: const Text('يظهر في أعلى الشاشة لجميع المستخدمين.'),
                    value: _announcementVisible,
                    onChanged: _isSaving ? null : (v) => setState(() => _announcementVisible = v),
                  ),
                  if (_announcementVisible) ...<Widget>[
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: _announcementTextController,
                      label: 'نص الإعلان',
                      hint: 'مثال: تحديث جديد متاح الآن!',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    const Text('درجة الأهمية:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment(value: 'info', label: Text('عادي')),
                        ButtonSegment(value: 'warning', label: Text('تحذير')),
                        ButtonSegment(value: 'critical', label: Text('هام جداً')),
                      ],
                      selected: {_announcementSeverity},
                      onSelectionChanged: _isSaving ? null : (v) => setState(() => _announcementSeverity = v.first),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // --- 3. Feature Flags ---
              _SectionCard(
                title: 'الميزات (Feature Flags)',
                icon: Icons.toggle_on_outlined,
                children: <Widget>[
                  SwitchListTile(
                    title: const Text('شاشة نقطة البيع (POS)'),
                    value: _flagPos,
                    onChanged: _isSaving ? null : (v) => setState(() => _flagPos = v),
                  ),
                  SwitchListTile(
                    title: const Text('شاشة المشتريات'),
                    value: _flagPurchases,
                    onChanged: _isSaving ? null : (v) => setState(() => _flagPurchases = v),
                  ),
                  SwitchListTile(
                    title: const Text('شاشة المخزون'),
                    value: _flagInventory,
                    onChanged: _isSaving ? null : (v) => setState(() => _flagInventory = v),
                  ),
                  SwitchListTile(
                    title: const Text('شاشة التقارير'),
                    value: _flagReports,
                    onChanged: _isSaving ? null : (v) => setState(() => _flagReports = v),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // --- Save Button ---
              AppButton(
                label: 'حفظ التغييرات',
                icon: Icons.save_outlined,
                expanded: true,
                size: AppButtonSize.large,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _save,
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const Divider(height: 24),
          ...children,
        ],
      ),
    );
  }
}
