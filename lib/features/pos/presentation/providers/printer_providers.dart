// lib/features/pos/presentation/providers/printer_providers.dart

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences_storage.dart';
import '../../data/services/pos_preferences.dart';
import '../../data/services/printer_service.dart';
import '../../domain/entities/printer_device.dart';

/// Provides the singleton [PrinterService] for the app session.
final Provider<PrinterService> printerServiceProvider =
    Provider<PrinterService>((ref) {
  final PrinterService service = FlutterPosPrinterService();
  ref.onDispose(() {
    // Best-effort release; errors are swallowed by the service.
    // ignore: discarded_futures
    service.disconnect();
  });
  return service;
});

/// Persists and exposes the user's default printer.
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
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return SavedPrinter.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  /// Persists [printer] as the default and updates the state.
  Future<void> save(SavedPrinter printer) async {
    final SavedPrinter? previous = state.valueOrNull;
    if (!_isDisposed) {
      state = AsyncData<SavedPrinter?>(printer);
    }

    try {
      final PreferencesStorage storage =
          await ref.read(preferencesStorageProvider.future);
      await storage.writeString(
        key: PosPreferences.savedPrinterKey,
        value: jsonEncode(printer.toJson()),
      );
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        state = AsyncData<SavedPrinter?>(previous);
      }
      rethrow;
    }
  }

  /// Clears the saved printer.
  Future<void> clear() async {
    final SavedPrinter? previous = state.valueOrNull;
    if (!_isDisposed) {
      state = const AsyncData<SavedPrinter?>(null);
    }

    try {
      final PreferencesStorage storage =
          await ref.read(preferencesStorageProvider.future);
      await storage.remove(key: PosPreferences.savedPrinterKey);
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        state = AsyncData<SavedPrinter?>(previous);
      }
      rethrow;
    }
  }
}

/// Provides the currently saved default printer, or `null`.
final AsyncNotifierProvider<SavedPrinterNotifier, SavedPrinter?>
    savedPrinterProvider =
    AsyncNotifierProvider<SavedPrinterNotifier, SavedPrinter?>(
  SavedPrinterNotifier.new,
);
