part of 'pdf_page_view.dart';

extension _PdfPageRaster on PdfPageViewState {
  /// Retains the current bitmap while native trackpad navigation is active.
  void _suspendRasterization() {
    _rasterizationSuspended = true;
    _rasterGeneration++;
    _pendingPageRaster = null;
    _pageTimer?.cancel();
    _pageTimer = null;
  }

  /// Allows a final viewport refresh after the gesture ends.
  void _resumeRasterization() {
    _rasterizationSuspended = false;
  }

  Future<void> _getImage(Size viewportSize, double zoomLevel) async {
    if (!mounted || _rasterizationSuspended || widget.pdfDocument == null) {
      return;
    }
    // One native request per page. Overlapping requests retain only the latest
    // target and invalidate the running result before allocating another image.
    if (_pageRasterRunning) {
      if (_runningPageZoom == zoomLevel &&
          _runningPageGeneration == _rasterGeneration &&
          _pendingPageRaster == null) {
        return;
      }
      _pendingPageRaster = (viewport: viewportSize, zoom: zoomLevel);
      _rasterGeneration++;
      return;
    }
    _calculateHeightPercentage();
    final double ratio = 1 / _heightPercentage;
    final double imageFactor = ratio * zoomLevel;
    if (_previousImageFactor == imageFactor) {
      return;
    }
    _isTile =
        ratio < 0.5 ||
        zoomLevel > 1.75 ||
        (!kIsDesktop && imageFactor > 2) ||
        (kIsDesktop && imageFactor > 4);
    if (_isTile && _pdfPage != null) {
      _previousImageFactor = imageFactor;
      return;
    }
    final Size originalSize = widget.pdfDocument!.pages[widget.pageIndex].size;
    final int width;
    final int height;
    if (_isTile) {
      final Size size =
          originalSize.width * originalSize.height * 4 <= 5 * 1024 * 1024
              ? originalSize
              : Size(widget.width, widget.height);
      width = size.width.toInt();
      height = size.height.toInt();
    } else {
      _tileImageCache = null;
      width = (widget.width * zoomLevel * _dpr).toInt();
      height = (widget.height * zoomLevel * _dpr).toInt();
    }
    if (width <= 0 || height <= 0) {
      return;
    }
    final int generation = ++_rasterGeneration;
    _pageRasterRunning = true;
    _runningPageZoom = zoomLevel;
    _runningPageGeneration = generation;
    final operation = CancelableOperation<Uint8List?>.fromFuture(
      PdfViewerPlatform.instance.getPage(
        widget.pageIndex + 1,
        width,
        height,
        widget.documentID,
      ),
    );
    _pageImageOperation = operation;
    final Stopwatch channelStopwatch = Stopwatch()..start();
    try {
      final Uint8List? pixels = await operation.valueOrCancellation();
      if (pixels == null ||
          !mounted ||
          _rasterizationSuspended ||
          generation != _rasterGeneration) {
        return;
      }
      final int channelMs = channelStopwatch.elapsedMilliseconds;
      final Stopwatch decodeStopwatch = Stopwatch()..start();
      // Dimensions belong to this request, never to a later zoom's state.
      final ui.Image image = await _createImage(pixels, width, height);
      if (!mounted ||
          _rasterizationSuspended ||
          generation != _rasterGeneration) {
        image.dispose();
        return;
      }
      final int decodeMs = decodeStopwatch.elapsedMilliseconds;
      _replacePageRaster(image, imageFactor);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.ohos) {
        final int renderedPage = widget.pageIndex + 1;
        final Stopwatch frameStopwatch = Stopwatch()..start();
        debugPrint(
          '[Syncfusion PDF][dartPage] page=$renderedPage '
          'size=${width}x$height bytes=${pixels.length} '
          'channelMs=$channelMs decodeMs=$decodeMs',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint(
            '[Syncfusion PDF][dartPageFrame] page=$renderedPage '
            'postFrameMs=${frameStopwatch.elapsedMilliseconds}',
          );
        });
      }
    } catch (_) {
      // Keep the previous bitmap if a native request or pixel decode fails.
    } finally {
      if (identical(_pageImageOperation, operation)) {
        _pageImageOperation = null;
      }
      _pageRasterRunning = false;
      _runningPageZoom = null;
      _runningPageGeneration = null;
      final pending = _pendingPageRaster;
      _pendingPageRaster = null;
      if (pending != null && mounted && !_rasterizationSuspended) {
        unawaited(_getImage(pending.viewport, pending.zoom));
      }
    }
  }

  Future<ui.Image> _createImage(Uint8List pixels, int width, int height) async {
    if (width <= 0 || height <= 0 || pixels.length < width * height * 4) {
      throw StateError('Incomplete PDF raster buffer');
    }
    // Awaitable decoding propagates errors to the request's catch block.
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      pixels,
    );
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    ui.Codec? codec;
    try {
      codec = await descriptor.instantiateCodec();
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
