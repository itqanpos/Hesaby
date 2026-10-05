// lib/features/pos/data/services/pos_preferences.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/preferences_storage.dart';
import 'pdf_receipt_builder.dart';

/// Centralises the POS-related preference keys and their typed accessors.
///
/// Currently the only persisted POS preference is the default paper size
/// used by the thermal printer dialog. It is stored as a plain string
/// (`'mm58'`, `'mm80'` or `'a4'`) so it stays human-readable in the
/// platform's preferences file.
abstract final class PosPreferences {
  /// Storage key for the default receipt paper size.
  static const String paperSizeKey = 'pos.paper_size';

  /// Default when nothing has been stored yet.
  ///
  /// 80 mm is the most common thermal roll width in Egypt and across the
  /// region, so it is a safe default for a fresh install.
  static const ReceiptPaperSize defaultPaperSize = ReceiptPaperSize.mm80;

  /// Parses a stored paper-size string, falling back to
  /// [defaultPaperSize] when the value is missing or unrecognised.
  static ReceiptPaperSize parsePaperSize(String? raw) {
    if (raw == null) {
      return defaultPaperSize;
    }
    for (final ReceiptPaperSize size in ReceiptPaperSize.values) {
      if (size.name == raw) {
        return size;
      }
    }
    return defaultPaperSize;
  }
}

/// Async holder of the current receipt paper size.
///
/// The notifier loads the stored value on first read and exposes
/// [setPaperSize] to persist a new value. Writes are optimistic: the new
/// state is published immediately, then persisted; on failure the
/// previous value is restored and the error is re-thrown so the caller
/// can surface a message.
///
/// Using a `bool _isDisposed` flag rather than `ref.mounted` because the
/// latter does not exist in Riverpod 2.x.
class PosPaperSizeNotifier extends AsyncNotifier<ReceiptPaperSize> {
  bool _isDisposed = false;

  @override
  Future<ReceiptPaperSize> build() async {
    ref.onDispose(() => _isDisposed = true);

    final PreferencesStorage storage =
        await ref.watch(preferencesStorageProvider.future);
    final String? raw = await storage.readString(
      key: PosPreferences.paperSizeKey,
    );
    return PosPreferences.parsePaperSize(raw);
  }

  /// Persists [size] as the new default paper size.
  ///
  /// The in-memory state is updated first so the UI reflects the choice
  /// immediately. If the write fails, the previous value is restored and
  /// the error is re-thrown.
  Future<void> setPaperSize(ReceiptPaperSize size) async {
    final ReceiptPaperSize? previous = state.valueOrNull;
    if (!_isDisposed) {
      state = AsyncData<ReceiptPaperSize>(size);
    }

    final PreferencesStorage storage =
        await ref.read(preferencesStorageProvider.future);

    try {
      await storage.writeString(
        key: PosPreferences.paperSizeKey,
        value: size.name,
      );
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        if (previous != null) {
          state = AsyncData<ReceiptPaperSize>(previous);
        } else {
          state = AsyncError<ReceiptPaperSize>(error, stackTrace);
        }
      }
      rethrow;
    }
  }
}

/// Exposes the current receipt paper size to the UI.
///
/// Consumers typically pattern-match on the [AsyncValue]:
/// * `data`  → use the value directly.
/// * `loading` → show a spinner or fall back to
///   [PosPreferences.defaultPaperSize].
/// * `error` → fall back to [PosPreferences.defaultPaperSize].
final posPaperSizeProvider =
    AsyncNotifierProvider<PosPaperSizeNotifier, ReceiptPaperSize>(
  PosPaperSizeNotifier.new,
);
