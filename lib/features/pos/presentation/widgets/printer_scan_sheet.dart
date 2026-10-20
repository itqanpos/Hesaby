// lib/features/pos/presentation/widgets/printer_scan_sheet.dart

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart' as pos;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/printer_device.dart';

/// Opens a bottom sheet to scan for available printers.
/// Returns the selected [PrinterDevice] or `null` if cancelled.
Future<PrinterDevice?> showPrinterScanSheet({required BuildContext context}) {
  return showModalBottomSheet<PrinterDevice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => const _PrinterScanSheet(),
  );
}

class _PrinterScanSheet extends StatefulWidget {
  const _PrinterScanSheet();

  @override
  State<_PrinterScanSheet> createState() => _PrinterScanSheetState();
}

class _PrinterScanSheetState extends State<_PrinterScanSheet> {
  bool _isLoading = true;
  String? _errorMessage;
  List<PrinterDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      List<PrinterDevice> found = [];

      if (kIsWeb) {
        _errorMessage = 'الطباعة المباشرة غير مدعومة على متصفح الويب.';
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // ⬇️ البحث عن طابعات USB للكمبيوتر (ويندوز / ماك / لينكس)
        final List<pos.PrinterDevice> usbDevices =
            await pos.PrinterManager.instance.discovery(type: pos.PrinterType.usb);

        found = usbDevices.map((d) {
          return PrinterDevice(
            name: d.name.isEmpty ? 'طابعة USB' : d.name,
            address: '${d.vendorId ?? "0"}:${d.productId ?? "0"}',
            connectionType: PrinterConnectionType.usb,
            vendorId: d.vendorId,
            productId: d.productId,
          );
        }).toList();
      } else {
        // ⬇️ البحث عن طابعات البلوتوث (أندرويد)
        final List<pos.PrinterDevice> btDevices =
            await pos.PrinterManager.instance.discovery(type: pos.PrinterType.bluetooth);

        found = btDevices.map((d) {
          return PrinterDevice(
            name: d.name.isEmpty ? 'طابعة بلوتوث' : d.name,
            address: d.address ?? '',
            connectionType: d.isBle
                ? PrinterConnectionType.bluetoothBle
                : PrinterConnectionType.bluetoothClassic,
          );
        }).toList();
      }

      if (mounted) {
        setState(() {
          _devices = found;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      AppLogger.error('Printer scan failed', e, s);
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذّر البحث عن الطابعات. تأكد من تشغيل البلوتوث أو توصيل كابل USB.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // الترويسة
          Row(
            children: <Widget>[
              Icon(Icons.print_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'اختيار طابعة',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // المحتوى
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.error_outline, color: scheme.error, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ],
              ),
            )
          else if (_devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.print_disabled_outlined, size: 40, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    'لم يتم العثور على طابعات.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Platform.isWindows 
                        ? 'تأكد من توصيل الطابعة بكابل USB وتعريفها في ويندوز.'
                        : 'تأكد من تشغيل البلوتوث وإقران الطابعة.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext ctx, int index) {
                  final PrinterDevice device = _devices[index];
                  final bool isUsb = device.connectionType == PrinterConnectionType.usb;
                  
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isUsb ? Icons.usb : Icons.bluetooth,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      device.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      isUsb ? 'USB' : (device.connectionType == PrinterConnectionType.bluetoothBle ? 'Bluetooth BLE' : 'Bluetooth Classic'),
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () => Navigator.of(context).pop(device),
                  );
                },
              ),
            ),

          const SizedBox(height: 16),
          
          // زر إعادة البحث
          if (!_isLoading)
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.search),
              label: const Text('بحث مرة أخرى'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
        ],
      ),
    );
  }
}
