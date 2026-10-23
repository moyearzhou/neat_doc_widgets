import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Owns pixels until Flutter has imported them, including stale render replies.
class PdfRasterBuffer {
  PdfRasterBuffer.bytes(this._bytes) : _file = null;
  PdfRasterBuffer._file(this._file) : _bytes = null;

  static const MethodChannel _channel = MethodChannel(
    'syncfusion_flutter_pdfviewer',
  );
  final Uint8List? _bytes;
  final Map<Object?, Object?>? _file;
  Future<void>? _release;

  /// Android files avoid large platform-message payloads and let the engine
  /// copy pixels on its concurrent runner through ImmutableBuffer.fromFilePath.
  /// Other platforms keep their existing platform implementation unchanged.
  static Future<PdfRasterBuffer?> render(
    String method,
    Map<String, Object> arguments,
    Future<Uint8List?> Function() legacy,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      final bytes = await legacy();
      return bytes == null ? null : PdfRasterBuffer.bytes(bytes);
    }
    final result = await _channel.invokeMethod<Object?>(method, {
      ...arguments,
      'rasterFile': true,
    });
    // Older native plugins may ignore the opt-in and return their byte API.
    if (result == null || result is Uint8List) {
      return result == null ? null : PdfRasterBuffer.bytes(result as Uint8List);
    }
    return PdfRasterBuffer._file(result as Map<Object?, Object?>);
  }

  Future<ui.ImmutableBuffer> importBuffer(int expectedBytes) async {
    try {
      if (_release != null) {
        throw StateError('PDF raster buffer already released');
      }
      final ui.ImmutableBuffer buffer;
      if (_file != null) {
        if (_file['byteLength'] != expectedBytes || _file['path'] is! String) {
          throw StateError('Incomplete PDF raster file');
        }
        buffer = await ui.ImmutableBuffer.fromFilePath(
          _file['path']! as String,
        );
      } else {
        if (_bytes == null || _bytes.length < expectedBytes) {
          throw StateError('Incomplete PDF raster buffer');
        }
        buffer = await ui.ImmutableBuffer.fromUint8List(_bytes);
      }
      if (buffer.length < expectedBytes) {
        buffer.dispose();
        throw StateError('Incomplete imported PDF raster buffer');
      }
      return buffer;
    } finally {
      // Releases share the renderer worker. Do not delay image decoding behind
      // another page's render just to unlink an already imported file.
      unawaited(dispose());
    }
  }

  Future<void> dispose() => _release ??= _dispose();

  Future<void> _dispose() async {
    final token = _file?['token'];
    if (token == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('releaseRasterFile', token);
    } on PlatformException {
      // Engine detach also removes outstanding files on the native worker.
    } on MissingPluginException {
      // A reply can outlive the engine during teardown.
    }
  }
}
