// lib/features/pos/presentation/widgets/printer_scan_sheet.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../data/services/printer_service.dart';
import '../../domain/entities/printer_device.dart';
import '../providers/printer_providers.dart';

/// Opens the printer-scan bottom sheet and returns the picked device,
/// or `null` when the user cancels.
Future<PrinterDevice?> showPrinterScanSheet({
  required BuildContext context,
}) {
  return showModalBottomSheet<PrinterDevice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => const _PrinterScanSheet(),
  );
}

// ============================================================================
// Sheet
// ============================================================================

class _PrinterScanSheet extends ConsumerStatefulWidget {
  const _PrinterScanSheet();

  @override
  ConsumerState<_PrinterScanSheet> createState() =>
      _PrinterScanSheetState();
}

class _PrinterScanSheetState extends ConsumerState<_PrinterScanSheet> {
  PrinterConnectionType _type = PrinterConnectionType.bluetoothClassic;

  StreamSubscription<PrinterDevice>? _sub;
  final List<PrinterDevice> _found = <PrinterDevice>[];
  final Set<String> _seenIds = <String>{};

  bool _isScanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------

  Future<void> _startScan() async {
    await _sub?.cancel();

    setState(() {
      _found.clear();
      _seenIds.clear();
      _isScanning = true;
      _error = null;
    });

    final PrinterService service = ref.read(printerServiceProvider);

    _sub = service.discover(_type).listen(
      (PrinterDevice device) {
        if (!mounted) return;
        if (_seenIds.add(device.id)) {
          setState(() => _found.add(device));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error('Printer scan failed', error, stackTrace);
        if (!mounted) return;
        setState(() {
          _error = 'تعذّر البحث عن الطابعات.';
          _isScanning = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isScanning = false);
      },
      cancelOnError: false,
    );

    // Hard-stop after 15s so the spinner never runs forever.
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (_isScanning) {
        setState(() => _isScanning = false);
      }
    });
  }

  void _changeType(PrinterConnectionType next) {
    if (next == _type) return;
    setState(() => _type = next);
    _startScan();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.print_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'اختيار طابعة',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ---- Type selector ----
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<PrinterConnectionType>(
                  segments: const <ButtonSegment<PrinterConnectionType>>[
                    ButtonSegment<PrinterConnectionType>(
                      value: PrinterConnectionType.bluetoothClassic,
                      label: Text('بلوتوث قديم'),
                      icon: Icon(Icons.bluetooth),
                    ),
                    ButtonSegment<PrinterConnectionType>(
                      value: PrinterConnectionType.bluetoothBle,
                      label: Text('بلوتوث BLE'),
                      icon: Icon(Icons.bluetooth_searching),
                    ),
                    ButtonSegment<PrinterConnectionType>(
                      value: PrinterConnectionType.usb,
                      label: Text('USB'),
                      icon: Icon(Icons.usb),
                    ),
                    ButtonSegment<PrinterConnectionType>(
                      value: PrinterConnectionType.network,
                      label: Text('شبكة'),
                      icon: Icon(Icons.wifi),
                    ),
                  ],
                  selected: <PrinterConnectionType>{_type},
                  onSelectionChanged: (Set<PrinterConnectionType> sel) {
                    if (sel.isEmpty) return;
                    _changeType(sel.first);
                  },
                  showSelectedIcon: false,
                ),
              ),
              const SizedBox(height: 8),

              // ---- Hint ----
              Text(
                _hintFor(_type),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              // ---- Results ----
              if (_error != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                )
              else if (_found.isEmpty && _isScanning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_found.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'لم يتم العثور على أي طابعة. تأكد من تشغيل الطابعة '
                    'وأنها في وضع الاقتران.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _found.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (BuildContext itemContext, int index) {
                      final PrinterDevice device = _found[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.print_outlined),
                        ),
                        title: Text(device.name),
                        subtitle: Text(
                          device.address.isEmpty ? '—' : device.address,
                        ),
                        onTap: () =>
                            Navigator.of(context).pop(device),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 12),

              // ---- Rescan ----
              FilledButton.tonalIcon(
                onPressed: _isScanning ? null : _startScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isScanning ? 'جاري البحث…' : 'إعادة البحث'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _hintFor(PrinterConnectionType type) {
    switch (type) {
      case PrinterConnectionType.bluetoothClassic:
        return 'معظم الطابعات الحرارية الرخيصة تستخدم هذا النوع.';
      case PrinterConnectionType.bluetoothBle:
        return 'طابعات حديثة تعمل ببطارية غالبًا.';
      case PrinterConnectionType.usb:
        return 'طابعة موصولة بكابل USB (Android فقط).';
      case PrinterConnectionType.network:
        return 'طابعة على نفس شبكة الواي فاي.';
    }
  }
}
