// test/responsive_helper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabi/core/responsive/responsive_helper.dart';

void main() {
  group('ResponsiveHelper.deviceTypeOf', () {
    test('mobile below 600', () {
      expect(ResponsiveHelper.deviceTypeOf(0), DeviceType.mobile);
      expect(ResponsiveHelper.deviceTypeOf(320), DeviceType.mobile);
      expect(ResponsiveHelper.deviceTypeOf(599), DeviceType.mobile);
    });

    test('tablet from 600 to 1023', () {
      expect(ResponsiveHelper.deviceTypeOf(600), DeviceType.tablet);
      expect(ResponsiveHelper.deviceTypeOf(800), DeviceType.tablet);
      expect(ResponsiveHelper.deviceTypeOf(1023), DeviceType.tablet);
    });

    test('desktop from 1024 to 1439', () {
      expect(ResponsiveHelper.deviceTypeOf(1024), DeviceType.desktop);
      expect(ResponsiveHelper.deviceTypeOf(1280), DeviceType.desktop);
      expect(ResponsiveHelper.deviceTypeOf(1439), DeviceType.desktop);
    });

    test('wide desktop from 1440', () {
      expect(ResponsiveHelper.deviceTypeOf(1440), DeviceType.wideDesktop);
      expect(ResponsiveHelper.deviceTypeOf(2560), DeviceType.wideDesktop);
    });
  });

  group('ResponsiveHelper.gridColumns', () {
    test('maps each device class to a column count', () {
      expect(ResponsiveHelper.gridColumns(DeviceType.mobile), 1);
      expect(ResponsiveHelper.gridColumns(DeviceType.tablet), 2);
      expect(ResponsiveHelper.gridColumns(DeviceType.desktop), 3);
      expect(ResponsiveHelper.gridColumns(DeviceType.wideDesktop), 4);
    });
  });

  group('ResponsiveHelper.contentWidthFor', () {
    test('clamps to the maximum content width', () {
      expect(ResponsiveHelper.contentWidthFor(400), 400);
      expect(
        ResponsiveHelper.contentWidthFor(4000),
        ResponsiveHelper.contentMaxWidth,
      );
    });
  });

  group('ResponsiveHelper.horizontalPadding', () {
    test('grows with the device class', () {
      final double mobile = ResponsiveHelper.horizontalPadding(
        DeviceType.mobile,
      );
      final double wide = ResponsiveHelper.horizontalPadding(
        DeviceType.wideDesktop,
      );

      expect(mobile, lessThan(wide));
      expect(mobile, greaterThan(0));
    });
  });
}
