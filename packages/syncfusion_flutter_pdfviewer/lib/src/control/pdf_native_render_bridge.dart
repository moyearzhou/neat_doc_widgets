import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';

/// Sends viewport intent to the OHOS queue independently of pixel format.
class PdfNativeRenderBridge {
  const PdfNativeRenderBridge();
  static const MethodChannel _channel = MethodChannel(
    'syncfusion_flutter_pdfviewer',
  );

  bool get _usesNativeQueue =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.ohos;

  Future<Uint8List?> getPage(
    int page,
    int width,
    int height,
    String documentID, {
    required bool visible,
  }) {
    if (!_usesNativeQueue) {
      return PdfViewerPlatform.instance.getPage(
        page,
        width,
        height,
        documentID,
      );
    }
    // Keep the existing RGBA contract. Priority must not depend on BGRA/RGBA.
    return _channel.invokeMethod<Uint8List>('getPage', <String, Object>{
      'index': page,
      'width': width,
      'height': height,
      'documentID': documentID,
      'renderPriority': visible ? 0 : 1,
    });
  }

  Future<void> updateState(
    String documentID,
    int page, {
    required bool active,
    required bool visible,
    bool invalidate = false,
  }) async {
    if (!_usesNativeQueue) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('updateRenderState', <String, Object>{
        'documentID': documentID,
        'index': page,
        'active': active,
        'visible': visible,
        'invalidate': invalidate,
      });
    } on MissingPluginException {
      // Hot reload can pair new Dart code with the previous native binary.
      // Rendering remains available; queue cancellation requires a rebuild.
    }
  }
}
