// lib/features/pos/presentation/providers/printer_providers.dart

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences_storage.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/printer_service.dart';
import '../../domain/entities/printer_device.dart';

/// مزود خدمة الطابعة المركزية.
/// 
/// يستخدم [PrinterServiceImpl] التي قمنا بإعدادها لدعم USB، الشبكة، والبلوتوث.
final Provider<PrinterService> printerServiceProvider = Provider<PrinterService>((ref) {
  return PrinterServiceImpl();
});

/// مزود الطابعة المحفوظة.
/// 
/// يقوم بقراءة وحفظ بيانات الطابعة (الاسم، العنوان، النوع) من التخزين المحلي
/// (SharedPreferences) لضمان بقاء الاتصال محفوظاً حتى بعد إغلاق التطبيق.
final AsyncNotifierProvider<SavedPrinterNotifier, SavedPrinter?>
    savedPrinterProvider =
    AsyncNotifierProvider<SavedPrinterNotifier, SavedPrinter?>(
  SavedPrinterNotifier.new,
);

class SavedPrinterNotifier extends AsyncNotifier<SavedPrinter?> {
  @override
  Future<SavedPrinter?> build() async {
    final PreferencesStorage storage =
        await ref.watch(preferencesStorageProvider.future);

    final String? raw = await storage.readString(
      key: PosPreferences.savedPrinterKey,
    );

    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final Map<String, dynamic> map =
          jsonDecode(raw) as Map<String, dynamic>;
      return SavedPrinter.fromJson(map);
    } on Object {
      // إذا كانت البيانات المحفوظة تالفة أو غير متوافقة، نرجع null
      // ونمسحها لتجنب أي انهيار.
      await storage.remove(key: PosPreferences.savedPrinterKey);
      return null;
    }
  }

  /// حفظ طابعة جديدة واستبدال القديمة.
  Future<void> save(SavedPrinter printer) async {
    final PreferencesStorage storage =
        await ref.read(preferencesStorageProvider.future);

    await storage.writeString(
      key: PosPreferences.savedPrinterKey,
      value: jsonEncode(printer.toJson()),
    );

    if (!ref.mounted) return; // حماية من التحديث بعد التدمير
    state = AsyncData<SavedPrinter?>(printer);
  }

  /// مسح الطابعة المحفوظة (نسيان الطابعة).
  Future<void> clear() async {
    final PreferencesStorage storage =
        await ref.read(preferencesStorageProvider.future);

    await storage.remove(key: PosPreferences.savedPrinterKey);

    if (!ref.mounted) return;
    state = const AsyncData<SavedPrinter?>(null);
  }
}
