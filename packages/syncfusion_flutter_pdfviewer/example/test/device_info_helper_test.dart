import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/common/device_info_helper.dart';

void main() {
  test('queries Android device info only on Android', () {
    expect(
      shouldQueryAndroidDeviceInfo(isAndroid: true, isFlutterTest: false),
      isTrue,
    );
    expect(
      shouldQueryAndroidDeviceInfo(isAndroid: false, isFlutterTest: false),
      isFalse,
      reason: 'HarmonyOS must not deserialize its payload as Android data',
    );
    expect(
      shouldQueryAndroidDeviceInfo(isAndroid: true, isFlutterTest: true),
      isFalse,
    );
  });
}
