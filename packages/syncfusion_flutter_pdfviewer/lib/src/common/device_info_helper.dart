/// Android device info must only deserialize payloads produced on Android.
bool shouldQueryAndroidDeviceInfo({
  required bool isAndroid,
  required bool isFlutterTest,
}) => isAndroid && !isFlutterTest;
