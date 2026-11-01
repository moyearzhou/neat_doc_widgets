part of 'pdf_page_view.dart';

extension _PdfPageRaster on PdfPageViewState {
  /// Retains the current bitmap while native trackpad navigation is active.
  void _suspendRasterization() {
    _rasterizationSuspended = true;
    _rasterGeneration++;
    _updateNativeRenderState(invalidate: true);
    _pendingPageRaster = null;
    _pendingDetail = null;
    _pageTimer?.cancel();
    _pageTimer = null;
  }

  /// Allows a final viewport refresh after the gesture ends.
  void _resumeRasterization() {
    _rasterizationSuspended = false;
    _updateNativeRenderState();
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
      _updateNativeRenderState(invalidate: true);
      return;
    }
    _calculateHeightPercentage();
    final double ratio = 1 / _heightPercentage;
    final double imageFactor = ratio * zoomLevel;
    if (_previousImageFactor == imageFactor &&
        _baseRasterDpr == _dpr &&
        (!_baseRasterIsPreview || !_pageVisible)) {
      return;
    }
    int width = (widget.width * zoomLevel * _dpr).ceil();
    int height = (widget.height * zoomLevel * _dpr).ceil();
    // Choose by actual output pixels, not desktop/mobile identity. A small
    // viewport can retain a full-DPI page; a large one gets a bounded base
    // plus high-DPI detail patches.
    _isTile = width * height * 4 > 16 * 1024 * 1024;
    if (_isTile && _pdfPage != null) {
      _previousImageFactor = imageFactor;
      _baseRasterDpr = _dpr;
      return;
    }
    if (_isTile) {
      // The base is a fallback, not a second full-DPI copy of the detail image.
      final double scale = math.min(
        1,
        math.sqrt(4 * 1024 * 1024 / (width * height * 4)),
      );
      width = math.max(1, (width * scale).floor());
      height = math.max(1, (height * scale).floor());
    }
    final bool preview = !_pageVisible;
    if (preview) {
      // Prefetch useful first pixels without retaining full-DPI neighbors.
      final double scale = math.min(1, 768 / width);
      width = math.max(1, (width * scale).floor());
      height = math.max(1, (height * scale).floor());
    }
    // Cap even unusually tall neighbor previews at 16MiB. Detail rendering
    // restores viewport density without a huge full-page allocation.
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
      _renderWhenCurrent(() {
        _nativeRenderRequested = true;
        return _nativeRenderBridge.getPage(
          widget.pageIndex + 1,
          width,
          height,
          widget.documentID,
          visible: _pageVisible,
        );
      }, generation),
    );
    _pageImageOperation = operation;
    final Stopwatch channelStopwatch = Stopwatch()..start();
    try {
      final Uint8List? pixels = await operation.valueOrCancellation();
      if (pixels == null &&
          mounted &&
          _viewportActive &&
          _pageVisible &&
          !_rasterizationSuspended &&
          generation == _rasterGeneration &&
          _pdfPage == null) {
        widget.onPageRasterFailed?.call(widget.pageIndex + 1);
      }
      if (pixels == null ||
          !mounted ||
          !_viewportActive ||
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
      _baseRasterIsPreview = preview;
      _baseRasterDpr = _dpr;
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
      if (mounted &&
          _viewportActive &&
          _pageVisible &&
          !_rasterizationSuspended &&
          generation == _rasterGeneration &&
          _pdfPage == null) {
        widget.onPageRasterFailed?.call(widget.pageIndex + 1);
      }
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
      } else {
        final detail = _pendingDetail;
        _pendingDetail = null;
        if (detail != null &&
            mounted &&
            _viewportActive &&
            !_rasterizationSuspended) {
          unawaited(
            _getDetailImage(
              detail.transform,
              detail.viewport,
              detail.zoom,
              prefetch: detail.prefetch,
            ),
          );
        }
      }
    }
  }

  void _updateNativeRenderState({bool invalidate = false}) {
    // A pinch visits every page state. Notify only pages that reached native,
    // and do not repeatedly invalidate already inactive native work.
    if (!_nativeRenderRequested) {
      return;
    }
    final bool active = _viewportActive && !_rasterizationSuspended;
    if (_nativeReportedActive == active &&
        _nativeReportedVisible == _pageVisible &&
        (!invalidate || !active)) {
      return;
    }
    _nativeReportedActive = active;
    _nativeReportedVisible = _pageVisible;
    unawaited(
      _nativeRenderBridge.updateState(
        widget.documentID,
        widget.pageIndex + 1,
        active: active,
        visible: _pageVisible,
        invalidate: invalidate,
      ),
    );
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
