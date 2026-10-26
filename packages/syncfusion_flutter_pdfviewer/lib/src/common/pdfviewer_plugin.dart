import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';
import 'package:uuid/uuid.dart';

/// Establishes communication between native(Android and iOS) code
/// and flutter code using [MethodChannel]
class PdfViewerPlugin {
  int _pageCount = 0;
  List<dynamic>? _originalHeight;
  List<dynamic>? _originalWidth;
  String? _documentID;
  String? _tempFilePath;
  Future<void> _initialization = Future.value();
  Future<void>? _closing;

  /// Initialize the PDF renderer.
  Future<int> initializePdfRenderer(Uint8List documentBytes, String? password) {
    final result = _initialize(documentBytes, password);
    _initialization = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<int> _initialize(Uint8List documentBytes, String? password) async {
    await _closing;
    _documentID = const Uuid().v1();
    String? pageCount;
    if (_documentID != null) {
      if (kIsWeb) {
        pageCount = await PdfViewerPlatform.instance.initializePdfRenderer(
          documentBytes,
          _documentID!,
          password,
        );
      } else {
        final tempDirectory = await Directory.systemTemp.createTemp('pdf_');
        final tempFile = File(
          '${tempDirectory.path}${Platform.pathSeparator}${_documentID!}.pdf',
        );
        await tempFile.writeAsBytes(documentBytes, flush: true);
        _tempFilePath = tempFile.path;
        pageCount = await PdfViewerPlatform.instance.loadPdfFromFile(
          tempFile.path,
          _documentID!,
          password,
        );
      }
    }
    _pageCount = int.parse(pageCount!);
    return _pageCount;
  }

  /// Get the current document ID
  String get documentID => _documentID ?? '';

  /// Retrieves original height of PDF pages.
  Future<List<dynamic>?> getPagesHeight() async {
    _originalHeight = await PdfViewerPlatform.instance.getPagesHeight(
      _documentID!,
    );
    return _originalHeight;
  }

  /// Retrieves original width of PDF pages.
  Future<List<dynamic>?> getPagesWidth() async {
    _originalWidth = await PdfViewerPlatform.instance.getPagesWidth(
      _documentID!,
    );
    return _originalWidth;
  }

  /// Dispose the rendered pages
  Future<void> closeDocument() =>
      _closing ??= _close().whenComplete(() {
        _closing = null;
      });

  Future<void> _close() async {
    // A reader may be disposed while native initialization is still in flight.
    // Wait for that attempt before closing/deleting; late init must not leak a handle.
    final pending = _initialization;
    await pending;
    imageCache.clear();
    if (_documentID != null) {
      await PdfViewerPlatform.instance.closeDocument(_documentID!);
    }
    if (!kIsWeb && _tempFilePath != null) {
      final file = File(_tempFilePath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
    _pageCount = 0;
    _originalWidth = null;
    _originalHeight = null;
    _tempFilePath = null;
    _documentID = null;
  }
}

/// Represents the RenderedImage.
class RenderedImage {
  /// Initializes RenderedImage properties.
  RenderedImage(int index, double currentScale) {
    pageIndex = index;
    scale = currentScale;
  }

  /// Page index of RenderedImage
  late final int pageIndex;

  /// Scale value of RenderedImage
  late final double scale;
}
