// lib/shared/widgets/offline_banner.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/network_status_provider.dart';

/// Auto-hiding banner that appears at the top of the app when the device
/// loses connectivity.
///
/// Takes **zero height** while online, so it is safe to always include it
/// in [AppShell]. The show/hide transition is animated to avoid layout
/// jank when the network flaps.
///
/// Placement: should be inserted *inside* the shell's `SafeArea` (below
/// the status bar on mobile) and *above* the page content.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isOnline = ref.watch(isOnlineProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: isOnline
          ? const SizedBox(width: double.infinity, height: 0)
          : const _BannerBody(),
    );
  }
}

class _BannerBody extends StatelessWidget {
  const _BannerBody();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // Amber palette — follows Material's warning convention and reads
    // clearly in both light and dark themes.
    final Color background =
        isDark ? const Color(0xFF4A3B00) : const Color(0xFFFFF3CD);
    final Color foreground =
        isDark ? const Color(0xFFFFE082) : const Color(0xFF7A5C00);

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'لا يوجد اتصال بالإنترنت — بعض الميزات غير متاحة.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
