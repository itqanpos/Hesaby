// lib/features/pos/presentation/providers/printer_providers.dart

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences_storage.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/printer_service.dart';
import '../../domain/entities/printer_device.dart';

final Provider<PrinterService> printerServiceProvider = Provider<PrinterService>((ref) {
  return PrinterServiceImpl();
});

final AsyncNotifierProvider<SavedPrinterNotifier, SavedPrinter?>
    savedPrinterProvider =
    AsyncNotifierProvider<SavedPrinterNotifier, SavedPrinter?>(
  SavedPrinterNotifier.new,
);

class SavedPrinterNotifier extends AsyncNotifier<SavedPrinter?> {
  bool _isDisposed = false;

  @override
  Future<SavedPrinter?> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);

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
      await storage.remove(key: PosPreferences.savedPrinterKey);
      return null;
    }
  }

  Future<void> save(SavedPrinter printer) async {
    final PreferencesStorage storage =
        await ref.read(preferencesStorageProvider.future);

    await storage.writeString(
      key: PosPreferences.savedPrinterKey,
      value: jsonEncode(printer.toJson()),
    );

    if (_isDisposed) return;
    state = AsyncData<SavedPrinter?>(printer);
  }

  Future<void> clear() async {
    final PreferencesStorage storage =
        await ref.read(preferencesStorageProvider.future);

    await storage.remove(key: PosPreferences.savedPrinterKey);

    if (_isDisposed) return;
    state = const AsyncData<SavedPrinter?>(null);
  }
}
