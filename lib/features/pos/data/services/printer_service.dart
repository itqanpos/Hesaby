// lib/features/pos/data/services/printer_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart' as pos;

import '../../domain/entities/printer_device.dart';

enum PrinterFailureType {
  notSupported,
  connectFailed,
  notConnected,
  sendFailed,
  unknown,
}

class PrinterException implements Exception {
  const PrinterException(this.type, [this.message]);
  final PrinterFailureType type;
  final String? message;

  @override
  String toString() => 'PrinterException(type: $type, message: $message)';
}

abstract interface class PrinterService {
  bool get isConnected;
  Future<bool> connect(PrinterDevice device);
  Future<void> disconnect();
  Future<void> sendBytes(List<int> bytes);
  Future<List<PrinterDevice>> getUsbDevices();
}

class PrinterServiceImpl implements PrinterService {
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<bool> connect(PrinterDevice device) async {
    try {
      if (_isConnected) await disconnect();

      if (device.connectionType == PrinterConnectionType.usb) {
        await pos.PrinterManager.instance.connect(
          type: pos.PrinterType.usb,
          model: pos.UsbPrinterInput(
            name: device.name,
            productId: device.productId ?? '',
            vendorId: device.vendorId ?? '',
          ),
        );
      } else if (device.connectionType == PrinterConnectionType.network) {
        await pos.PrinterManager.instance.connect(
          type: pos.PrinterType.network,
          model: pos.TcpPrinterInput(ipAddress: device.address),
        );
      } else if (device.connectionType == PrinterConnectionType.bluetoothClassic ||
          device.connectionType == PrinterConnectionType.bluetoothBle) {
        await pos.PrinterManager.instance.connect(
          type: pos.PrinterType.bluetooth,
          model: pos.BluetoothPrinterInput(
            name: device.name,
            address: device.address,
            isBle: device.connectionType == PrinterConnectionType.bluetoothBle,
          ),
        );
      } else {
        throw const PrinterException(PrinterFailureType.notSupported);
      }

      _isConnected = true;
      return true;
    } catch (e) {
      debugPrint('Printer Connect Error: $e');
      _isConnected = false;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await pos.PrinterManager.instance.disconnect(type: pos.PrinterType.usb);
      await pos.PrinterManager.instance.disconnect(type: pos.PrinterType.network);
      await pos.PrinterManager.instance.disconnect(type: pos.PrinterType.bluetooth);
    } catch (_) {}
    _isConnected = false;
  }

  @override
  Future<void> sendBytes(List<int> bytes) async {
    if (!_isConnected) {
      throw const PrinterException(PrinterFailureType.notConnected);
    }
    try {
      await pos.PrinterManager.instance.send(
        type: pos.PrinterType.usb, // المكتبة تتجاهلها إذا لم تكن USB
        bytes: bytes,
      );
    } catch (e) {
      throw PrinterException(PrinterFailureType.sendFailed, e.toString());
    }
  }

  @override
  Future<List<PrinterDevice>> getUsbDevices() async {
    try {
      // ⬇️ استخدام .toList() مع الـ Stream لتحويله إلى List
      final List<pos.PrinterDevice> usbDevices = await pos.PrinterManager.instance
          .discovery(type: pos.PrinterType.usb)
          .toList();

      return usbDevices.map((d) {
        return PrinterDevice(
          name: d.name.isEmpty ? 'طابعة USB' : d.name,
          address: '${d.vendorId ?? "0"}:${d.productId ?? "0"}',
          connectionType: PrinterConnectionType.usb,
          vendorId: d.vendorId,
          productId: d.productId,
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to discover USB devices: $e');
      return [];
    }
  }
}
