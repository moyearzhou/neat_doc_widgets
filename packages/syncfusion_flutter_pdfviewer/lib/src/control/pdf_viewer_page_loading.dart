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

  void _disposePageText() {
    _visiblePageText?.dispose();
    _visiblePageText = null;
    _pageTextWorker?.dispose();
    _pageTextWorker = null;
  }

  void _handleSemanticsChanged() {
    if (!SemanticsBinding.instance.semanticsEnabled) {
      _disposePageText();
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
