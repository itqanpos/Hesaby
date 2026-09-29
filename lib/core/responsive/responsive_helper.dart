// lib/core/responsive/responsive_helper.dart
import 'package:flutter/widgets.dart';

import '../../app/config/app_constants.dart';

/// The layout class a given width belongs to.
enum DeviceType { mobile, tablet, desktop, wideDesktop }

/// Centralised responsive calculations.
///
/// Breakpoints:
/// * mobile: `< 600`
/// * tablet: `600 – 1023`
/// * desktop: `1024 – 1439`
/// * wide desktop: `>= 1440`
abstract final class ResponsiveHelper {
  static const double contentMaxWidth = AppConstants.contentMaxWidth;

  static DeviceType deviceTypeOf(double width) {
    if (width < AppConstants.breakpointMobile) {
      return DeviceType.mobile;
    }
    if (width < AppConstants.breakpointTablet) {
      return DeviceType.tablet;
    }
    if (width < AppConstants.breakpointDesktop) {
      return DeviceType.desktop;
    }
    return DeviceType.wideDesktop;
  }

  static DeviceType deviceTypeOfContext(BuildContext context) =>
      deviceTypeOf(MediaQuery.sizeOf(context).width);

  static double horizontalPadding(DeviceType deviceType) =>
      switch (deviceType) {
        DeviceType.mobile => 16,
        DeviceType.tablet => 24,
        DeviceType.desktop => 32,
        DeviceType.wideDesktop => 40,
      };

  static int gridColumns(DeviceType deviceType) => switch (deviceType) {
        DeviceType.mobile => 1,
        DeviceType.tablet => 2,
        DeviceType.desktop => 3,
        DeviceType.wideDesktop => 4,
      };

  /// Clamps [availableWidth] to the maximum readable content width.
  static double contentWidthFor(double availableWidth) =>
      availableWidth > contentMaxWidth ? contentMaxWidth : availableWidth;
}

/// Convenience accessors for the current layout class.
extension ResponsiveContext on BuildContext {
  DeviceType get deviceType => ResponsiveHelper.deviceTypeOfContext(this);

  bool get isMobileLayout => deviceType == DeviceType.mobile;

  bool get isTabletLayout => deviceType == DeviceType.tablet;

  bool get isDesktopLayout => deviceType == DeviceType.desktop;

  bool get isWideDesktopLayout => deviceType == DeviceType.wideDesktop;
}
