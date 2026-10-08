// lib/features/pos/data/services/printer_service.dart

import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart'
    as fpp;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/printer_device.dart';

/// Categories of printer failures the UI can translate to Arabic.
enum PrinterFailureType {
  /// The current platform does not expose any printer transport.
  notSupported,

  /// The connection attempt failed (printer off, out of range, busy).
  connectFailed,

  /// The caller tried to send bytes without an active connection.
  notConnected,

  /// The bytes could not be sent (connection lost mid-transfer).
  sendFailed,

  /// Any other unclassified failure.
  unknown,
}

/// Domain-level exception raised by [PrinterService].
class PrinterException implements Exception {
  const PrinterException(this.type, {this.cause});

  final PrinterFailureType type;
  final Object? cause;

  @override
  String toString() => 'PrinterException(${type.name})';
}

/// Contract for discovering, connecting to, and sending bytes to a
/// thermal printer over Bluetooth / USB / network.
abstract interface class PrinterService {
  /// Whether a printer is currently connected.
  bool get isConnected;

  /// The currently connected device, or `null`.
  PrinterDevice? get connectedDevice;

  /// Emits discovered devices of the given [type] until the stream is
  /// cancelled.
  ///
  /// Each call starts a fresh scan; the caller is expected to cancel the
  /// subscription when done. On a platform where the transport is not
  /// available, the stream completes immediately without emitting.
  Stream<PrinterDevice> discover(PrinterConnectionType type);

  /// Connects to [device]. Returns `true` on success.
  Future<bool> connect(PrinterDevice device);

  /// Disconnects the current printer, if any. Safe to call repeatedly.
  Future<void> disconnect();

  /// Sends raw ESC/POS [bytes] to the connected printer.
  ///
  /// Throws [PrinterException] with [PrinterFailureType.notConnected]
  /// when called without an active connection.
  Future<void> sendBytes(List<int> bytes);
}

/// Default [PrinterService] backed by
/// `flutter_pos_printer_platform_image_3`.
///
/// The service is stateful: it remembers the currently connected device
/// so [sendBytes] does not require the caller to pass it every time.
/// It is not thread-safe; concurrent [connect] calls are undefined.
///
/// The plugin distinguishes the three transports via `PrinterType`, and
/// uses a `isBle` boolean on Bluetooth calls to select between Classic
/// SPP (default) and BLE. This service maps domain-side
/// [PrinterConnectionType] to that shape.
class FlutterPosPrinterService implements PrinterService {
  FlutterPosPrinterService();

  final fpp.PrinterManager _manager = fpp.PrinterManager.instance;

  PrinterDevice? _connected;
  fpp.PrinterType? _connectedManagerType;

  @override
  bool get isConnected => _connected != null;

  @override
  PrinterDevice? get connectedDevice => _connected;

  @override
  Stream<PrinterDevice> discover(PrinterConnectionType type) {
    final fpp.PrinterType managerType = _toManagerType(type);
    final bool isBle = type == PrinterConnectionType.bluetoothBle;

    return _manager
        .discovery(type: managerType, isBle: isBle)
        .map((fpp.PrinterDevice device) => _toDomain(device, type));
  }

  @override
  Future<bool> connect(PrinterDevice device) async {
    // Always drop any previous connection first — a printer cannot be
    // reached over two transports at once.
    await disconnect();

    try {
      final fpp.PrinterType managerType = _toManagerType(device.connectionType);
      final fpp.BasePrinterInput input = _toManagerInput(device);

      final bool ok = await _manager.connect(
        type: managerType,
        model: input,
      );

      if (ok) {
        _connected = device;
        _connectedManagerType = managerType;
      }
      return ok;
    } on Object catch (error, stackTrace) {
      AppLogger.error('Printer connect failed', error, stackTrace);
      _connected = null;
      _connectedManagerType = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    final fpp.PrinterType? type = _connectedManagerType;
    if (type != null) {
      try {
        await _manager.disconnect(type: type);
      } on Object catch (error, stackTrace) {
        AppLogger.error('Printer disconnect failed', error, stackTrace);
      }
    }
    _connected = null;
    _connectedManagerType = null;
  }

  @override
  Future<void> sendBytes(List<int> bytes) async {
    final fpp.PrinterType? type = _connectedManagerType;
    if (type == null) {
      throw const PrinterException(PrinterFailureType.notConnected);
    }
    try {
      final bool ok = await _manager.send(type: type, bytes: bytes);
      if (!ok) {
        throw const PrinterException(PrinterFailureType.sendFailed);
      }
    } on PrinterException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.error('Printer sendBytes failed', error, stackTrace);
      throw PrinterException(
        PrinterFailureType.sendFailed,
        cause: error,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  /// Maps a domain [PrinterConnectionType] to the plugin's [fpp.PrinterType].
  ///
  /// Both Bluetooth variants share the same plugin transport; the Classic
  /// vs BLE distinction is carried by the `isBle` flag on the plugin calls.
  static fpp.PrinterType _toManagerType(PrinterConnectionType type) {
    switch (type) {
      case PrinterConnectionType.bluetoothClassic:
      case PrinterConnectionType.bluetoothBle:
        return fpp.PrinterType.bluetooth;
      case PrinterConnectionType.usb:
        return fpp.PrinterType.usb;
      case PrinterConnectionType.network:
        return fpp.PrinterType.network;
    }
  }

  /// Builds the plugin-side input object matching [device]'s transport.
  ///
  /// Each transport has its own `*PrinterInput` class; the manager
  /// dispatches on the runtime type, so a wrong pairing throws at runtime.
  static fpp.BasePrinterInput _toManagerInput(PrinterDevice device) {
    switch (device.connectionType) {
      case PrinterConnectionType.bluetoothClassic:
        return fpp.BluetoothPrinterInput(
          address: device.address,
          name: device.name,
          isBle: false,
        );
      case PrinterConnectionType.bluetoothBle:
        return fpp.BluetoothPrinterInput(
          address: device.address,
          name: device.name,
          isBle: true,
        );
      case PrinterConnectionType.usb:
        return fpp.UsbPrinterInput(
          name: device.name,
          vendorId: device.vendorId,
          productId: device.productId,
        );
      case PrinterConnectionType.network:
        return fpp.TcpPrinterInput(ipAddress: device.address);
    }
  }

  /// Builds a domain [PrinterDevice] from a plugin-side device.
  static PrinterDevice _toDomain(
    fpp.PrinterDevice device,
    PrinterConnectionType type,
  ) {
    return PrinterDevice(
      name: device.name,
      address: device.address ?? '',
      connectionType: type,
      vendorId: device.vendorId,
      productId: device.productId,
    );
  }
}
