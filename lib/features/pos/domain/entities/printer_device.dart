// lib/features/pos/domain/entities/printer_device.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Connection method used by a thermal printer.
///
/// The distinction between [bluetoothClassic] and [bluetoothBle] is
/// surfaced to the user because the two protocols are physically
/// different: most budget thermal printers use the older Classic SPP
/// profile, while newer ones expose BLE. A single scanner cannot see
/// both at once, so the user chooses which to scan.
enum PrinterConnectionType {
  /// Bluetooth Classic (SPP). Common on low-cost 58mm / 80mm printers.
  bluetoothClassic,

  /// Bluetooth Low Energy. Common on newer, battery-powered printers.
  bluetoothBle,

  /// Wired USB printer.
  usb,

  /// Network printer (Wi-Fi / Ethernet), reached by IP address.
  network,
}

/// A printer discovered during a scan.
@immutable
class PrinterDevice extends Equatable {
  const PrinterDevice({
    required this.name,
    required this.address,
    required this.connectionType,
    this.vendorId,
    this.productId,
  });

  /// Human-readable name, e.g. "Xprinter XP-58".
  final String name;

  /// Platform-specific identifier: MAC address for Bluetooth, device
  /// path for USB, IP address for network.
  final String address;

  /// How this printer is reached.
  final PrinterConnectionType connectionType;

  /// USB vendor id (only meaningful for USB printers).
  final String? vendorId;

  /// USB product id (only meaningful for USB printers).
  final String? productId;

  /// Stable identifier used as a map key and in persistence.
  String get id => '${connectionType.name}:$address';

  /// Whether this device is reached over Bluetooth.
  bool get isBluetooth =>
      connectionType == PrinterConnectionType.bluetoothClassic ||
      connectionType == PrinterConnectionType.bluetoothBle;

  @override
  List<Object?> get props => <Object?>[
        name,
        address,
        connectionType,
        vendorId,
        productId,
      ];

  @override
  String toString() =>
      'PrinterDevice(name: $name, address: $address, '
      'type: ${connectionType.name})';
}

/// A printer the user has explicitly saved as their default.
///
/// Persisted to `PreferencesStorage` as JSON, so the app remembers the
/// user's printer across sessions and reconnects automatically on the
/// next print.
@immutable
class SavedPrinter extends Equatable {
  const SavedPrinter({
    required this.name,
    required this.address,
    required this.connectionType,
    this.vendorId,
    this.productId,
  });

  /// Builds a [SavedPrinter] from a discovered [device].
  factory SavedPrinter.fromDevice(PrinterDevice device) => SavedPrinter(
        name: device.name,
        address: device.address,
        connectionType: device.connectionType,
        vendorId: device.vendorId,
        productId: device.productId,
      );

  final String name;
  final String address;
  final PrinterConnectionType connectionType;

  /// USB vendor id, when applicable.
  final String? vendorId;

  /// USB product id, when applicable.
  final String? productId;

  /// Stable identifier, matching [PrinterDevice.id].
  String get id => '${connectionType.name}:$address';

  /// Reconstructs a [PrinterDevice] suitable for a reconnection attempt.
  PrinterDevice toDevice() => PrinterDevice(
        name: name,
        address: address,
        connectionType: connectionType,
        vendorId: vendorId,
        productId: productId,
      );

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'address': address,
        'connection_type': connectionType.name,
        'vendor_id': vendorId,
        'product_id': productId,
      };

  /// Parses a map produced by [toJson].
  ///
  /// Returns `null` when the payload is malformed or uses an unknown
  /// connection type — the caller should treat this as "no saved
  /// printer" rather than crashing.
  static SavedPrinter? fromJson(Map<String, dynamic> json) {
    final Object? name = json['name'];
    final Object? address = json['address'];
    final Object? typeRaw = json['connection_type'];
    if (name is! String || address is! String || typeRaw is! String) {
      return null;
    }
    PrinterConnectionType? type;
    for (final PrinterConnectionType candidate
        in PrinterConnectionType.values) {
      if (candidate.name == typeRaw) {
        type = candidate;
        break;
      }
    }
    if (type == null) {
      return null;
    }
    final Object? vendorId = json['vendor_id'];
    final Object? productId = json['product_id'];
    return SavedPrinter(
      name: name,
      address: address,
      connectionType: type,
      vendorId: vendorId is String ? vendorId : null,
      productId: productId is String ? productId : null,
    );
  }

  @override
  List<Object?> get props =>
      <Object?>[name, address, connectionType, vendorId, productId];

  @override
  String toString() =>
      'SavedPrinter(name: $name, address: $address, '
      'type: ${connectionType.name})';
}
