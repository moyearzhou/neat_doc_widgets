part of '../pdfviewer.dart';

extension _PdfViewerPageLoading on SfPdfViewerState {
  void _schedulePageRefresh() {
    if (_pageRefreshScheduled || !mounted) {
      return;
    }
    _pageRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageRefreshScheduled = false;
      if (mounted &&
          !_isTouchScaling &&
          !(_trackpadSession != null && _trackpadDidScale)) {
        _refreshVisiblePages();
      }
    });
  }

  /// Preserve a point on the first visible page, not a fraction of the whole
  /// document (mixed page sizes and spacing make that fraction drift).
  void _preserveReadingPosition(Size nextSize) {
    _viewportWidth = nextSize.width;
    _deviceOrientation = MediaQuery.of(context).orientation;
    if (nextSize == _viewportSize ||
        nextSize.isEmpty ||
        _viewportSize.isEmpty ||
        _pdfPages.isEmpty ||
        widget.pageLayoutMode != PdfPageLayoutMode.continuous) {
      return;
    }
    final int generation = ++_viewportResizeGeneration;
    final PdfDocument? document = _document;
    final double zoom = _transformationController.value[0];
    final Offset offset = _transformationController.toScene(Offset.zero);
    final List<int> visible = _visiblePageNumbers(
      offset & Size(_viewportSize.width / zoom, _viewportSize.height / zoom),
    );
    if (visible.isEmpty) {
      return;
    }
    final int number = visible.first;
    final PdfPageInfo page = _pdfPages[number]!;
    final bool vertical = _scrollDirection == PdfScrollDirection.vertical;
    final Offset origin =
        vertical ? Offset(0, page.pageOffset) : Offset(page.pageOffset, 0);
    final Offset relative = offset - origin;
    final Offset fraction = Offset(
      relative.dx / page.pageSize.width,
      relative.dy / page.pageSize.height,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _viewportResizeGeneration ||
          !identical(document, _document) ||
          vertical != (_scrollDirection == PdfScrollDirection.vertical) ||
          widget.pageLayoutMode != PdfPageLayoutMode.continuous) {
        return;
      }
      final PdfPageInfo? updated = _pdfPages[number];
      if (updated == null) {
        return;
      }
      final Offset newOrigin =
          vertical
              ? Offset(0, updated.pageOffset)
              : Offset(updated.pageOffset, 0);
      final Offset target =
          newOrigin +
          Offset(
            fraction.dx * updated.pageSize.width,
            fraction.dy * updated.pageSize.height,
          );
      // Let the scrollable receive its new content dimensions before clamping.
      _checkMount();
      _pdfScrollableStateKey.currentState?.forcePixels(target);
      _pdfPagesKey[number]?.currentState?.canvasRenderBox
          ?.updateContextMenuPosition();
    });
  }

  /// A leading throttle: repeated scroll updates keep the latest geometry,
  /// rather than postponing all high-DPI work until scrolling has stopped.
  void _scheduleDetailRefresh() {
    if (!mounted ||
        _isTouchScaling ||
        (_trackpadSession != null && _trackpadDidScale) ||
        _tileTimer != null) {
      return;
    }
    _tileTimer = Timer(const Duration(milliseconds: 80), () {
      _tileTimer = null;
      if (!mounted ||
          _isTouchScaling ||
          (_trackpadSession != null && _trackpadDidScale) ||
          _pdfPages.isEmpty ||
          _viewportSize.isEmpty) {
        return;
      }
      _refreshVisiblePages();
      final double zoom = _transformationController.value[0];
      final Offset offset = _transformationController.toScene(Offset.zero);
      final Rect view =
          offset &
          Size(_viewportSize.width / zoom, _viewportSize.height / zoom);
      final Rect ahead = view.inflate(
        (_scrollDirection == PdfScrollDirection.vertical
                ? view.height
                : view.width) *
            0.5,
      );
      final Iterable<int> nearby =
          widget.pageLayoutMode == PdfPageLayoutMode.single
              ? const <int>[]
              : _visiblePageNumbers(ahead);
      for (final int page in <int>{..._renderedImages, ...nearby}) {
        if (_cachedImagePages.contains(page)) {
          _pdfPagesKey[page]?.currentState?.getTileImage(
            _transformationController,
            _viewportSize,
            zoom,
            prefetch: !_renderedImages.contains(page),
          );
        }
      }
    });
  }

  HoverTextLoader _ensureHoverTextLoader() =>
      _hoverText ??= HoverTextLoader(
        extract: (int page, bool Function() isCurrent) async {
          if (!isCurrent() || _document == null) {
            return null;
          }
          if (kIsWeb) {
            // Web has no Dart isolates. Its fallback is deferred until scrolling
            // settles; native platforms never parse text on the pointer/UI thread.
            return extractHoverTextBounds(_document!, page);
          }
          _pageTextWorker ??= PageTextWorker(_pdfBytes, _password);
          return _pageTextWorker!.extractHoverBounds(page, isCurrent);
        },
      );

  void _disposePageText({bool documentChanged = true}) {
    _visiblePageText?.dispose();
    _visiblePageText = null;
    if (documentChanged) {
      _hoverText?.dispose();
      _hoverText = null;
      _pageTextWorker?.dispose();
      _pageTextWorker = null;
    }
  }

  void _handleSemanticsChanged() {
    if (!SemanticsBinding.instance.semanticsEnabled) {
      _disposePageText(documentChanged: false);
      for (final int page in _cachedImagePages) {
        _pdfPagesKey[page]?.currentState?.updateSemanticLabel(null);
      }
    } else if (mounted) {
      _updateVisiblePageText();
    }
  }

  void _updateVisiblePageText() {
    if (!SemanticsBinding.instance.semanticsEnabled || _document == null) {
      return;
    }
    _visiblePageText ??= VisiblePageTextLoader(
      extract: (int page) {
        // Web has no Dart isolates. Keep its extraction deferred and gated by
        // semantics; native platforms use one lazily initialized worker.
        if (kIsWeb) {
          return Future<String?>.value(
            _pdfTextExtractor?.extractText(startPageIndex: page),
          );
        }
        _pageTextWorker ??= PageTextWorker(_pdfBytes, _password);
        return _pageTextWorker!.extract(page);
      },
      onLoaded: (int page, String text) {
        if (mounted && _renderedImages.contains(page + 1)) {
          _pdfPagesKey[page + 1]?.currentState?.updateSemanticLabel(text);
        }
      },
    );
    for (final int page in _renderedImages) {
      _pdfPagesKey[page]?.currentState?.updateSemanticLabel(
        _visiblePageText!.textFor(page - 1),
      );
    }
    _visiblePageText!.setPages(_renderedImages.map((int page) => page - 1));
  }

  /// Page offsets are monotonic. Locate the first intersection in O(log n),
  /// then walk only pages intersecting the viewport, including at small zooms.
  List<int> _visiblePageNumbers(Rect viewport) {
    final bool vertical = _scrollDirection == PdfScrollDirection.vertical;
    final double start = vertical ? viewport.top : viewport.left;
    final double end = vertical ? viewport.bottom : viewport.right;
    final bool reversed = !vertical && _textDirection == TextDirection.rtl;
    int numberAt(int position) =>
        reversed ? _pdfPages.length + 1 - position : position;
    int low = 1;
    int high = _pdfPages.length;
    while (low < high) {
      final int middle = (low + high) ~/ 2;
      final PdfPageInfo page = _pdfPages[numberAt(middle)]!;
      final double length =
          vertical ? page.pageSize.height : page.pageSize.width;
      if (page.pageOffset + length <= start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final List<int> visible = <int>[];
    for (int position = low; position <= _pdfPages.length; position++) {
      final int number = numberAt(position);
      final PdfPageInfo page = _pdfPages[number]!;
      if (page.pageOffset >= end) {
        break;
      }
      final Rect bounds = Rect.fromLTWH(
        vertical ? 0 : page.pageOffset,
        vertical ? page.pageOffset : 0,
        page.pageSize.width,
        page.pageSize.height,
      );
      if (bounds.overlaps(viewport)) {
        visible.add(number);
      }
    }
    return visible;
  }

  void _refreshVisiblePages() {
    if (_pdfPages.isEmpty) {
      return;
    }
    final double zoom = _transformationController.value[0];
    final Offset offset = _transformationController.toScene(Offset.zero);
    final List<int> visible =
        widget.pageLayoutMode == PdfPageLayoutMode.single
            ? <int>[_pdfViewerController.pageNumber]
            : _visiblePageNumbers(
              Rect.fromLTWH(
                offset.dx,
                offset.dy,
                _viewportSize.width / zoom,
                _viewportSize.height / zoom,
              ),
            );
    if (visible.isNotEmpty &&
        _renderedImages.isNotEmpty &&
        visible.first != _renderedImages.first) {
      _pagePrefetchDirection = visible.first > _renderedImages.first ? 1 : -1;
    }
    final Set<int> desired = <int>{};
    for (final int page in visible) {
      for (
        int candidate = max(1, page - 2);
        candidate <= min(_pdfPages.length, page + 2);
        candidate++
      ) {
        desired.add(candidate);
      }
    }
    for (final int page in _cachedImagePages.difference(desired)) {
      _pdfPagesKey[page]?.currentState?.clearPageImage();
    }
    _cachedImagePages
      ..clear()
      ..addAll(desired);
    for (final int page in _renderedImages) {
      if (!visible.contains(page)) {
        _pdfPagesKey[page]?.currentState?.updateSemanticLabel(null);
      }
    }
    _renderedImages
      ..clear()
      ..addAll(visible);
    for (final int page in desired) {
      final PdfPageViewState? state = _pdfPagesKey[page]?.currentState;
      state?.setViewportActive(true, visible: visible.contains(page));
    }
    _trimPageImages();
    final neighbors =
        _cachedImagePages.where((page) => !visible.contains(page)).toList();
    if (visible.isNotEmpty) {
      int distance(int page) =>
          visible.map((current) => (page - current).abs()).reduce(min);
      neighbors.sort((a, b) {
        final distanceOrder = distance(a).compareTo(distance(b));
        return distanceOrder != 0
            ? distanceOrder
            : (b - a) * _pagePrefetchDirection;
      });
    }
    // Submit visible work before speculative neighbors, regardless of page order.
    for (final int page in <int>[...visible, ...neighbors]) {
      _pdfPagesKey[page]?.currentState?.getPageImage(_viewportSize, zoom);
    }
    _updateVisiblePageText();
  }

  void _trimPageImages() {
    int bytes = 0;
    for (final int page in _cachedImagePages) {
      if (!_renderedImages.contains(page)) {
        bytes += _pdfPagesKey[page]?.currentState?.rasterBytes ?? 0;
      }
    }
    // Visible images are never discarded to satisfy the soft cache limit.
    // Neighbor retention is bounded by bytes as well as page count.
    for (final int page in _cachedImagePages.toList()) {
      if (bytes <= 32 * 1024 * 1024) {
        break;
      }
      if (_renderedImages.contains(page)) {
        continue;
      }
      final PdfPageViewState? state = _pdfPagesKey[page]?.currentState;
      bytes -= state?.rasterBytes ?? 0;
      state?.clearPageImage();
      _cachedImagePages.remove(page);
    }
  }
}
