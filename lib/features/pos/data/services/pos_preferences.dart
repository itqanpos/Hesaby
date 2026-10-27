// lib/features/pos/data/services/pos_preferences.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences_storage.dart';
import 'pdf_receipt_builder.dart';

abstract final class PosPreferences {
  static const String paperSizeKey = 'pos.paper_size';
  static const String savedPrinterKey = 'pos.saved_printer';
  
  // ✅ مفتاح جديد للطباعة التلقائية
  static const String autoPrintKey = 'pos.auto_print';

  static const ReceiptPaperSize defaultPaperSize = ReceiptPaperSize.mm80;

  static ReceiptPaperSize parsePaperSize(String? raw) {
    if (raw == null) return defaultPaperSize;
    for (final ReceiptPaperSize size in ReceiptPaperSize.values) {
      if (size.name == raw) return size;
    }
    return defaultPaperSize;
  }
}

class PosPaperSizeNotifier extends AsyncNotifier<ReceiptPaperSize> {
  bool _isDisposed = false;

  @override
  Future<ReceiptPaperSize> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);

    final PreferencesStorage storage =
        await ref.watch(preferencesStorageProvider.future);
    final String? raw = await storage.readString(key: PosPreferences.paperSizeKey);
    return PosPreferences.parsePaperSize(raw);
  }

  Future<void> setPaperSize(ReceiptPaperSize size) async {
    final ReceiptPaperSize? previous = state.valueOrNull;
    if (!_isDisposed) state = AsyncData<ReceiptPaperSize>(size);

    final PreferencesStorage storage = await ref.read(preferencesStorageProvider.future);
    try {
      await storage.writeString(key: PosPreferences.paperSizeKey, value: size.name);
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        if (previous != null) state = AsyncData<ReceiptPaperSize>(previous);
        else state = AsyncError<ReceiptPaperSize>(error, stackTrace);
      }
      rethrow;
    }
  }
}

final posPaperSizeProvider =
    AsyncNotifierProvider<PosPaperSizeNotifier, ReceiptPaperSize>(
  PosPaperSizeNotifier.new,
);

// ============================================================================
// ✅ جديد: مزود الطباعة التلقائية
// ============================================================================

class AutoPrintNotifier extends AsyncNotifier<bool> {
  bool _isDisposed = false;

  @override
  Future<bool> build() async {
    _isDisposed = false;
    ref.onDispose(() => _isDisposed = true);

    final PreferencesStorage storage =
        await ref.watch(preferencesStorageProvider.future);
    final String? raw = await storage.readString(key: PosPreferences.autoPrintKey);
    
    // القيمة الافتراضية: false (لا يطبع تلقائياً إلا إذا فعّلها المستخدم)
    return raw == 'true';
  }

  Future<void> setAutoPrint(bool value) async {
    if (!_isDisposed) state = AsyncData<bool>(value);

    final PreferencesStorage storage = await ref.read(preferencesStorageProvider.future);
    await storage.writeString(key: PosPreferences.autoPrintKey, value: value.toString());
  }
}

final autoPrintProvider = AsyncNotifierProvider<AutoPrintNotifier, bool>(
  AutoPrintNotifier.new,
);
