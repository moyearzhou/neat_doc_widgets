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
    if (!mounted ||
        !_viewportActive ||
        _rasterizationSuspended ||
        widget.pdfDocument == null) {
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
    if (_previousImageFactor == imageFactor &&
        (!_baseRasterIsPreview || !_pageVisible)) {
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
    int width;
    int height;
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
    final bool preview = !_pageVisible;
    if (preview) {
      // Prefetch useful first pixels without retaining full-DPI neighbors.
      final double scale = math.min(1, 768 / width);
      width = math.max(1, (width * scale).floor());
      height = math.max(1, (height * scale).floor());
    }
    // Cap one base bitmap at 16MiB. Tile rendering restores viewport detail
    // after settling instead of allocating a huge full-page image at high DPI.
    final double reduction = math.min(
      1,
      math.sqrt(16 * 1024 * 1024 / (width * height * 4)),
    );
    if (reduction < 1) {
      width = math.max(1, (width * reduction).floor());
      height = math.max(1, (height * reduction).floor());
      _isTile = true;
    }
    if (width <= 0 || height <= 0) {
      return;
    }
    final int generation = ++_rasterGeneration;
    _pageRasterRunning = true;
    _runningPageZoom = zoomLevel;
    _runningPageGeneration = generation;
    final operation = CancelableOperation<Uint8List?>.fromFuture(
      _renderWhenCurrent(
        () => PdfViewerPlatform.instance.getPage(
          widget.pageIndex + 1,
          width,
          height,
          widget.documentID,
        ),
        generation,
      ),
    );
    _pageImageOperation = operation;
    try {
      final Uint8List? pixels = await operation.valueOrCancellation();
      if (pixels == null ||
          !mounted ||
          !_viewportActive ||
          _rasterizationSuspended ||
          generation != _rasterGeneration) {
        return;
      }
      // Dimensions belong to this request, never to a later zoom's state.
      final ui.Image image = await _createImage(pixels, width, height);
      if (!mounted ||
          _rasterizationSuspended ||
          generation != _rasterGeneration) {
        image.dispose();
        return;
      }
      _baseRasterIsPreview = preview;
      _replacePageRaster(image, imageFactor);
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
      if (pending != null &&
          mounted &&
          _viewportActive &&
          !_rasterizationSuspended) {
        unawaited(_getImage(pending.viewport, pending.zoom));
      } else if (preview &&
          mounted &&
          _viewportActive &&
          _pageVisible &&
          !_rasterizationSuspended &&
          _baseRasterIsPreview) {
        // A neighbor can enter the viewport while its preview is rendering.
        unawaited(_getImage(viewportSize, zoomLevel));
      }
    }
  }

  Future<Uint8List?> _renderWhenCurrent(
    Future<Uint8List?> Function() operation,
    int generation,
  ) {
    bool current() =>
        mounted &&
        _viewportActive &&
        !_rasterizationSuspended &&
        generation == _rasterGeneration;
    return widget.rasterQueue?.render(
          operation,
          current,
          isVisible: () => _pageVisible,
        ) ??
        (current() ? operation() : Future<Uint8List?>.value());
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
