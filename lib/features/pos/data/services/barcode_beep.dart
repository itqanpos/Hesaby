// lib/features/pos/data/services/barcode_beep.dart

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../../../../core/utils/logger.dart';

/// Plays a short "beep" when a barcode is scanned.
///
/// **No external asset is needed.** The WAV bytes are generated in memory
/// (a 3000 Hz sine wave with fade-in/out envelope) at first use, then
/// cached and reused. This works on Android, iOS, Web, and Desktop.
///
/// **Why not `flutter_beep`?** That package is unmaintained (last release
/// 2021) and may not build on Flutter 3.24+. `audioplayers` + a generated
/// WAV is the portable equivalent.
///
/// **Why not bundle a `.mp3`?** Because you asked for no external audio
/// files. The generated tone is indistinguishable from a bundled beep
/// on a device speaker.
class BarcodeBeep {
  BarcodeBeep._();

  static final BarcodeBeep instance = BarcodeBeep._();

  AudioPlayer? _player;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final AudioPlayer player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);

      final Uint8List wav = _generateBeepWav();
      await player.setSource(BytesSource(wav));

      _player = player;
      _initialized = true;
    } on Object catch (error) {
      AppLogger.warning('BarcodeBeep: init failed: $error');
    }
  }

  /// Plays the beep. Safe to call rapidly — restarts from the beginning.
  Future<void> play() async {
    try {
      await _ensureInitialized();
      final AudioPlayer? p = _player;
      if (p == null) return;
      await p.stop();
      await p.resume();
    } on Object catch (error) {
      AppLogger.warning('BarcodeBeep: play failed: $error');
    }
  }

  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _initialized = false;
  }

  // ---------------------------------------------------------------------------
  // WAV generation
  // ---------------------------------------------------------------------------

  /// Produces a 120 ms, 3000 Hz sine-wave "beep" as in-memory WAV bytes.
  ///
  /// * Mono, 16-bit PCM, 44100 Hz.
  /// * 5 ms fade-in / fade-out to avoid clicking artifacts.
  /// * Peak amplitude 0.6 (60 %) to avoid clipping.
  static Uint8List _generateBeepWav({
    int frequency = 3000,
    int durationMs = 120,
    int sampleRate = 44100,
  }) {
    final int numSamples = (sampleRate * durationMs / 1000).round();
    final int dataSize = numSamples * 2; // 16-bit mono
    final int fileSize = 44 + dataSize - 8;

    final ByteData header = ByteData(44);

    // "RIFF"
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, fileSize, Endian.little);

    // "WAVE"
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);

    // "fmt "
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);              // subchunk size
    header.setUint16(20, 1, Endian.little);               // PCM
    header.setUint16(22, 1, Endian.little);               // mono
    header.setUint32(24, sampleRate, Endian.little);      // sample rate
    header.setUint32(28, sampleRate * 2, Endian.little);  // byte rate
    header.setUint16(32, 2, Endian.little);               // block align
    header.setUint16(34, 16, Endian.little);              // bits per sample

    // "data"
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final Uint8List wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());

    final ByteData samples = wav.buffer.asByteData();
    final double omega = 2 * math.pi * frequency / sampleRate;
    final int fadeSamples = sampleRate ~/ 200; // 5 ms

    for (int i = 0; i < numSamples; i++) {
      double envelope = 1.0;
      if (i < fadeSamples) {
        envelope = i / fadeSamples;
      } else if (i > numSamples - fadeSamples) {
        envelope = (numSamples - i) / fadeSamples;
      }
      final double value = 0.6 * envelope * 32767 * math.sin(omega * i);
      samples.setInt16(44 + i * 2, value.toInt(), Endian.little);
    }

    return wav;
  }
}
