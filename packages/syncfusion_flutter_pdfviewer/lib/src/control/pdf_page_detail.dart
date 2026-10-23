part of 'pdf_page_view.dart';

extension _PdfPageDetail on PdfPageViewState {
  ({Rect page, Rect visible, Size viewport, double scale})? _detailTarget(
    TransformationController transform,
    Size viewport,
    double zoom, {
    required bool prefetch,
  }) {
    if (!mounted ||
        !_viewportActive ||
        _rasterizationSuspended ||
        widget.pdfDocument == null ||
        viewport.isEmpty ||
        zoom <= 0 ||
        (zoom - transform.value[0]).abs() > 0.0001) {
      return null;
    }
    _calculateHeightPercentage();
    final Offset origin =
        widget.isSinglePageView
            ? Offset.zero
            : widget.scrollDirection == PdfScrollDirection.vertical
            ? Offset(0, widget.pdfPages[widget.pageIndex + 1]!.pageOffset)
            : Offset(widget.pdfPages[widget.pageIndex + 1]!.pageOffset, 0);
    final Rect page = origin & Size(widget.width, widget.height);
    final Offset offset = transform.toScene(Offset.zero);
    Rect view = offset & Size(viewport.width / zoom, viewport.height / zoom);
    // Prewarm only the nearby part of a neighbor, never every cached page.
    // Visible detail always has higher queue priority than this speculation.
    if (prefetch) {
      view =
          widget.scrollDirection == PdfScrollDirection.vertical
              ? view.inflate(view.height * 0.5)
              : view.inflate(view.width * 0.5);
    }
    final Rect exposed = page.intersect(view);
    if (exposed.isEmpty || exposed.hasNaN) {
      return null;
    }
    Rect toPage(Rect rect) => Rect.fromLTRB(
      (rect.left - origin.dx) * _heightPercentage,
      (rect.top - origin.dy) * _heightPercentage,
      (rect.right - origin.dx) * _heightPercentage,
      (rect.bottom - origin.dy) * _heightPercentage,
    );
    return (
      page: toPage(page),
      visible: toPage(exposed),
      viewport: Size(
        viewport.width / zoom * _heightPercentage,
        viewport.height / zoom * _heightPercentage,
      ),
      scale: zoom * _dpr / _heightPercentage,
    );
  }

  Future<void> _getDetailImage(
    TransformationController transform,
    Size viewport,
    double zoom, {
    required bool prefetch,
  }) async {
    if (_detailTarget(transform, viewport, zoom, prefetch: prefetch) == null) {
      return;
    }
    // Retain only the newest requested viewport while native work runs.
    if (_tileImageOperation != null || _pageRasterRunning) {
      _pendingDetail = (
        transform: transform,
        viewport: viewport,
        zoom: zoom,
        prefetch: prefetch,
      );
      return;
    }
    await _getImage(viewport, zoom);
    final target = _detailTarget(transform, viewport, zoom, prefetch: prefetch);
    if (target == null || !_isTile || _tileImageOperation != null) {
      return;
    }
    if (_tileImageCache?.region.covers(
          target.page,
          target.visible,
          target.scale,
        ) ??
        false) {
      return;
    }
    final PdfDetailRegion region = PdfDetailRegion.plan(
      target.page,
      target.visible,
      target.scale,
      viewportSize: target.viewport,
    );
    final Size size = region.imageSize;
    final int generation = _rasterGeneration;
    bool current() {
      final latest = _detailTarget(
        transform,
        viewport,
        zoom,
        prefetch: prefetch,
      );
      return generation == _rasterGeneration &&
          latest != null &&
          (latest.scale - region.pixelScale).abs() < 0.0001 &&
          region.bounds.overlaps(latest.visible);
    }

    Future<PdfRasterBuffer?>? operation;
    PdfRasterBuffer? pixels;
    try {
      operation =
          widget.rasterQueue?.renderResource<PdfRasterBuffer>(
            () => _renderDetail(region, size),
            current,
            isVisible: () => _pageVisible,
            onDiscard: (buffer) => unawaited(buffer.dispose()),
          ) ??
          (current() ? _renderDetail(region, size) : Future.value());
      _tileImageOperation = operation;
      pixels = await operation;
      if (pixels == null || !current()) {
        return;
      }
      final ui.Image image = await _createImage(
        pixels,
        size.width.toInt(),
        size.height.toInt(),
      );
      if (!current()) {
        image.dispose();
        return;
      }
      _replaceDetailRaster(image, region);
    } catch (_) {
      // A failing page leaves the existing raster visible, without retry loops.
    } finally {
      await pixels?.dispose();
      if (identical(_tileImageOperation, operation)) {
        _tileImageOperation = null;
        final pending = _pendingDetail;
        _pendingDetail = null;
        if (pending != null &&
            mounted &&
            _viewportActive &&
            !_rasterizationSuspended) {
          unawaited(
            _getDetailImage(
              pending.transform,
              pending.viewport,
              pending.zoom,
              prefetch: pending.prefetch,
            ),
          );
        }
      }
    }
  }

  Future<PdfRasterBuffer?> _renderDetail(PdfDetailRegion region, Size size) =>
      PdfRasterBuffer.render(
        'getTileImage',
        {
          'pageNumber': widget.pageIndex + 1,
          'scale': region.pixelScale,
          'x': region.bounds.left,
          'y': region.bounds.top,
          'width': size.width,
          'height': size.height,
          'documentID': widget.documentID,
        },
        () => PdfViewerPlatform.instance.getTileImage(
          widget.pageIndex + 1,
          region.pixelScale,
          region.bounds.left,
          region.bounds.top,
          size.width,
          size.height,
          widget.documentID,
        ),
      );
}
