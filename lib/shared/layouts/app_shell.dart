// lib/shared/layouts/app_shell.dart

import 'package:flutter/material.dart';

import '../../core/responsive/responsive_helper.dart';

/// Standard page scaffold used across HESABI.
///
/// It applies safe-area handling, responsive horizontal padding and the
/// project's maximum content width.
///
/// [resizeToAvoidBottomInset] is forwarded to the underlying [Scaffold]:
/// * `true` (default) — the body shrinks when the soft keyboard appears,
///   pushing any bottom-anchored widget above the keyboard. This is the
///   right choice for most form pages.
/// * `false` — the body keeps its full height, and the keyboard simply
///   overlays whatever is at the bottom. Used by the POS page, where the
///   cashier expects the pay panel to stay put and be covered by the
///   keyboard.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.applyHorizontalPadding = true,
    this.constrainContentWidth = true,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final bool applyHorizontalPadding;
  final bool constrainContentWidth;

  /// Forwarded to [Scaffold.resizeToAvoidBottomInset].
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final DeviceType deviceType = context.deviceType;
    final double horizontalPadding = applyHorizontalPadding
        ? ResponsiveHelper.horizontalPadding(deviceType)
        : 0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constrainContentWidth
                  ? ResponsiveHelper.contentMaxWidth
                  : double.infinity,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
