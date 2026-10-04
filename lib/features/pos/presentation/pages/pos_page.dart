// lib/features/pos/presentation/pages/pos_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive_helper.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../widgets/pos_header.dart';
import 'pos_desktop_layout.dart';
import 'pos_mobile_layout.dart';
import 'pos_tablet_layout.dart';

/// POS main page — responsive shell.
///
/// The page is intentionally minimal. Its only responsibility is to read
/// the available width and delegate the actual layout to one of three
/// concrete widgets:
///
/// * [PosMobileLayout]   for mobile (`< 600 dp`),
/// * [PosTabletLayout]   for tablet (`600 – 1023 dp`),
/// * [PosDesktopLayout]  for desktop and wide desktop (`>= 1024 dp`).
///
/// All POS business logic lives in the notifier layer
/// (`posCartProvider`, `posSearchProvider`). All visual composition lives
/// in the individual layouts and their widgets. This page holds no state,
/// no providers, and no business rules.
class PosPage extends ConsumerWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      appBar: const PosHeader(),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : ResponsiveHelper.contentMaxWidth;
          final DeviceType deviceType = ResponsiveHelper.deviceTypeOf(width);

          return switch (deviceType) {
            DeviceType.mobile => const PosMobileLayout(),
            DeviceType.tablet => const PosTabletLayout(),
            DeviceType.desktop ||
            DeviceType.wideDesktop =>
              const PosDesktopLayout(),
          };
        },
      ),
    );
  }
}
