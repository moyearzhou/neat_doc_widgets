import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';

import '../common/mobile_helper.dart'
    if (dart.library.js_interop) '../common/web_helper.dart'
    as helper;

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

  Future<Uint8List?> getTileImage(
    int page,
    double scale,
    double x,
    double y,
    double width,
    double height,
    String documentID, {
    required bool visible,
  }) {
    if (!_usesNativeQueue) {
      return PdfViewerPlatform.instance.getTileImage(
        page,
        scale,
        x,
        y,
        width,
        height,
        documentID,
      );
    }
    // Detail prewarming uses the same viewport priority and cancellation as
    // base images; a nearby patch must never overtake visible page work.
    return _channel.invokeMethod<Uint8List>('getTileImage', <String, Object>{
      'pageNumber': page,
      'scale': scale,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'documentID': documentID,
      'renderPriority': visible ? 0 : 1,
    });
  }

  /// OHOS returns a small native handle instead of a GC-accounted RGBA array.
  /// Older binaries and other platforms retain their existing pixel protocol.
  Future<PdfNativePixelBuffer?> getDetailBuffer(
    int page,
    double scale,
    double x,
    double y,
    double width,
    double height,
    String documentID, {
    required bool visible,
  }) async {
    if (_usesNativeQueue) {
      try {
        final int? handle = await _channel
            .invokeMethod<int>('getTileBuffer', <String, Object>{
              'pageNumber': page,
              'scale': scale,
              'x': x,
              'y': y,
              'width': width,
              'height': height,
              'documentID': documentID,
              'renderPriority': visible ? 0 : 1,
            });
        if (handle == null) {
          return null;
        }
        try {
          return PdfNativePixelBuffer(
            helper.nativePdfPixels(handle, width.toInt() * height.toInt() * 4),
            () => helper.releaseNativePdfPixels(handle),
          );
        } catch (_) {
          helper.releaseNativePdfPixels(handle);
          rethrow;
        }
      } on MissingPluginException {
        // A hot reload can pair new Dart code with an older native plugin.
      }
    }
    final pixels = await getTileImage(
      page,
      scale,
      x,
      y,
      width,
      height,
      documentID,
      visible: visible,
    );
    return pixels == null ? null : PdfNativePixelBuffer(pixels, () {});
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

/// Owns a native allocation or a legacy byte result. Disposal is idempotent so
/// stale queue results and decode failures share the same release contract.
class PdfNativePixelBuffer {
  PdfNativePixelBuffer(Uint8List pixels, this._release) : _pixels = pixels;

  Uint8List? _pixels;
  final VoidCallback _release;

  Uint8List get pixels =>
      _pixels ?? (throw StateError('PDF pixel buffer has been released'));

  void dispose() {
    if (_pixels == null) {
      return;
    }
    // Drop the borrowed view before freeing its backing allocation.
    _pixels = null;
    _release();
  }
}
