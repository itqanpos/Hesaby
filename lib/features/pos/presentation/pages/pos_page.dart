// lib/features/pos/presentation/pages/pos_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/responsive_helper.dart';
import '../../../../shared/layouts/app_shell.dart';
import '../../domain/entities/pos_cart.dart';
import '../dialogs/pos_payment_dialog.dart';
import '../state/pos_focus_providers.dart';
import '../state/pos_providers.dart';
import '../widgets/pos_header.dart';
import 'pos_desktop_layout.dart';
import 'pos_mobile_layout.dart';
import 'pos_tablet_layout.dart';

/// POS main page — responsive shell + keyboard shortcuts.
///
/// Layout selection is delegated to one of three concrete widgets based on
/// available width. Business logic lives entirely in the notifier layer.
///
/// Keyboard shortcuts (desktop / web):
/// * **F2**  — focus the search field.
/// * **F9**  — open the payment dialog (no-op on an empty cart).
/// * **Esc** — clear the search query.
///
/// The page is rendered with `resizeToAvoidBottomInset: false` so that the
/// bottom pay panel stays pinned at the bottom of the screen and is simply
/// covered by the on-screen keyboard. This matches how POS apps behave:
/// the cashier types into the search field while the pay panel stays out
/// of the way.
class PosPage extends ConsumerWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppShell(
      resizeToAvoidBottomInset: false,
      appBar: const PosHeader(),
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.f2): () =>
              _focusSearch(ref),
          const SingleActivator(LogicalKeyboardKey.f9): () =>
              _handlePay(context, ref),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _clearSearch(ref),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : ResponsiveHelper.contentMaxWidth;
              final DeviceType deviceType =
                  ResponsiveHelper.deviceTypeOf(width);

              return switch (deviceType) {
                DeviceType.mobile => const PosMobileLayout(),
                DeviceType.tablet => const PosTabletLayout(),
                DeviceType.desktop ||
                DeviceType.wideDesktop =>
                  const PosDesktopLayout(),
              };
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shortcut handlers
  // ---------------------------------------------------------------------------

  void _focusSearch(WidgetRef ref) {
    ref.read(posSearchFocusNodeProvider).requestFocus();
  }

  void _clearSearch(WidgetRef ref) {
    ref.read(posSearchProvider.notifier).clear();
  }

  void _handlePay(BuildContext context, WidgetRef ref) {
    final PosCart cart = ref.read(posCartProvider);
    if (cart.isEmpty) {
      return;
    }
    showPosPaymentDialog(context: context);
  }
}
