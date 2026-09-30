// lib/shared/layouts/responsive_layout.dart

import 'package:flutter/material.dart';

import '../../core/responsive/responsive_helper.dart';

/// Builds a different subtree per device class, falling back to the
/// closest smaller layout when a variant is not supplied.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.wideDesktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;
  final Widget? wideDesktop;

  @override
  Widget build(BuildContext context) {
    final DeviceType deviceType = context.deviceType;

    return switch (deviceType) {
      DeviceType.mobile => mobile,
      DeviceType.tablet => tablet ?? mobile,
      DeviceType.desktop => desktop ?? tablet ?? mobile,
      DeviceType.wideDesktop => wideDesktop ?? desktop ?? tablet ?? mobile,
    };
  }
}
