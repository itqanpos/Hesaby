// lib/features/pos/data/services/printer_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

import '../../domain/entities/printer_device.dart';

/// أنواع الأخطاء التي قد تحدث أثناء الاتصال أو الطباعة.
enum PrinterFailureType {
  notSupported,
  connectFailed,
  notConnected,
  sendFailed,
  unknown,
}

/// استثناء مخصص لأخطاء الطابعة.
class PrinterException implements Exception {
  const PrinterException(this.type, [this.message]);
  final PrinterFailureType type;
  final String? message;

  @override
  String toString() => 'PrinterException(type: $type, message: $message)';
}

/// واجهة خدمة الطابعة.
abstract interface class PrinterService {
  bool get isConnected;
  Future<bool> connect(PrinterDevice device);
  Future<void> disconnect();
  Future<void> sendBytes(List<int> bytes);
  
  /// جلب طابعات USB المتصلة (مفيد جداً في ويندوز).
  Future<List<PrinterDevice>> getUsbDevices();
}

/// التنفيذ الفعلي لخدمة الطابعة باستخدام مكتبة flutter_pos_printer_platform.
class PrinterServiceImpl implements PrinterService {
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  // ---------------------------------------------------------------------------
  // الاتصال
  // ---------------------------------------------------------------------------

  @override
  Future<bool> connect(PrinterDevice device) async {
    try {
      // التأكد من قطع الاتصال القديم أولاً
      if (_isConnected) {
        await disconnect();
      }

      if (device.connectionType == PrinterConnectionType.usb) {
        // ⬇️ اتصال USB (يدعم الويندوز والأندرويد بشكل ممتاز)
        await PrinterManager.instance.connect(
          type: PrinterType.usb,
          model: UsbPrinterInput(
            name: device.name,
            productId: device.productId,
            vendorId: device.vendorId,
          ),
        );
      } else if (device.connectionType == PrinterConnectionType.network) {
        // ⬇️ اتصال شبكة (TCP/IP)
        await PrinterManager.instance.connect(
          type: PrinterType.network,
          model: TcpPrinterInput(ipAddress: device.address),
        );
      } else if (device.connectionType == PrinterConnectionType.bluetoothClassic ||
          device.connectionType == PrinterConnectionType.bluetoothBle) {
        // ⬇️ اتصال بلوتوث (يدعم الأندرويد فقط)
        await PrinterManager.instance.connect(
          type: PrinterType.bluetooth,
          model: BluetoothPrinterInput(
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

  // ---------------------------------------------------------------------------
  // قطع الاتصال
  // ---------------------------------------------------------------------------

  @override
  Future<void> disconnect() async {
    try {
      await PrinterManager.instance.disconnect(type: PrinterType.usb);
      await PrinterManager.instance.disconnect(type: PrinterType.network);
      await PrinterManager.instance.disconnect(type: PrinterType.bluetooth);
    } catch (_) {
      // تجاهل الأخطاء إذا كانت الطابعة مفصولة بالفعل
    } finally {
      _isConnected = false;
    }
  }

  // ---------------------------------------------------------------------------
  // إرسال البيانات (الطباعة)
  // ---------------------------------------------------------------------------

  @override
  Future<void> sendBytes(List<int> bytes) async {
    if (!_isConnected) {
      throw const PrinterException(PrinterFailureType.notConnected);
    }

    try {
      // إرسال البيانات كـ RAW BYTES (وهو ما ينتجه EscPosReceiptBuilder)
      await PrinterManager.instance.send(
        type: PrinterType.usb, // سيتم تجاهلها إذا كانت متصلة بشبكة أو بلوتوث
        bytes: bytes,
      );
    } catch (e) {
      // في بعض الأحيان تفشل الطابعات في استقبال البيانات لأسباب مختلفة
      throw PrinterException(PrinterFailureType.sendFailed, e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // اكتشاف طابعات USB (للويندوز)
  // ---------------------------------------------------------------------------

  @override
  Future<List<PrinterDevice>> getUsbDevices() async {
    try {
      // جلب أجهزة USB من النظام
      final List<PrinterDeviceInfo> usbDevices =
          await PrinterManager.instance.discovery(type: PrinterType.usb);

      return usbDevices.map((device) {
        return PrinterDevice(
          name: device.name,
          // في USB، قد لا يكون هناك عنوان MAC، فنستخدم الـ ID
          address: '${device.vendorId}:${device.productId}',
          connectionType: PrinterConnectionType.usb,
          vendorId: device.vendorId,
          productId: device.productId,
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to discover USB devices: $e');
      return [];
    }
  }
}
