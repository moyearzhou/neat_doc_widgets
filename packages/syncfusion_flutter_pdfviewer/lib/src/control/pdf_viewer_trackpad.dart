part of '../pdfviewer.dart';

extension _PdfViewerTrackpad on SfPdfViewerState {
  Widget _withTrackpadNavigation(Widget child) =>
      PdfTrackpadGestureRegion(onEvent: _handleTrackpadGesture, child: child);

  void _handleTrackpadGesture(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerScrollInertiaCancelEvent ||
        event is PointerScrollEvent) {
      _trackpadMomentum.stop();
      return;
    }
    if (!mounted || _pdfViewerController.pageCount == 0 || isBookmarkViewOpen) {
      _trackpadMomentum.stop();
      _trackpadSession = null;
      _trackpadPointer = null;
      _trackpadVelocity = null;
      return;
    }
    if (event is PointerPanZoomStartEvent) {
      final RenderObject? render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize) {
        return;
      }
      if (_trackpadPointer != null) {
        return;
      }
      if (widget.pageLayoutMode == PdfPageLayoutMode.continuous &&
          _pdfScrollableStateKey.currentState == null) {
        return;
      }
      if (widget.pageLayoutMode == PdfPageLayoutMode.single &&
          _singlePageViewKey.currentState == null) {
        return;
      }
      _trackpadMomentum.stop();
      _trackpadDidScale = false;
      _trackpadVelocity = VelocityTracker.withKind(PointerDeviceKind.trackpad)
        ..addPosition(event.timeStamp, Offset.zero);
      _trackpadPointer = event.pointer;
      _trackpadSession = PdfTrackpadSession(
        zoom: _pdfViewerController.zoomLevel,
        focalPoint: widget.pageLayoutMode == PdfPageLayoutMode.single
            ? _singlePageViewKey.currentState!.trackpadFocalPoint(
                event.position,
              )
            : render.globalToLocal(event.position),
        transform: widget.pageLayoutMode == PdfPageLayoutMode.single
            ? _singlePageViewKey.currentState!.trackpadTransform
            : _transformationController,
      );
      _hideTextSelectionMenu();
      _hideStickyNoteDialog();
    } else if (event is PointerPanZoomUpdateEvent) {
      final PdfTrackpadSession? session = _trackpadSession;
      if (session == null ||
          _trackpadPointer != event.pointer ||
          !event.scale.isFinite ||
          event.scale <= 0 ||
          !event.pan.dx.isFinite ||
          !event.pan.dy.isFinite) {
        return;
      }
      final target = session.resolve(
        scale: event.scale,
        pan: event.pan,
        minZoom: _minScale,
        maxZoom: widget.maxZoomLevel,
      );
      _trackpadVelocity?.addPosition(event.timeStamp, event.pan);
      _trackpadDidScale = _trackpadDidScale || (event.scale - 1).abs() > .0001;
      _applyTrackpadViewport(target.zoom, target.offset);
    } else if (event is PointerPanZoomEndEvent &&
        _trackpadPointer == event.pointer) {
      final Offset velocity =
          _trackpadVelocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
      _trackpadSession = null;
      _trackpadPointer = null;
      _trackpadVelocity = null;
      if (!_trackpadDidScale) {
        _trackpadMomentum.start(
          // Controller offsets may be mirrored for right-to-left navigation.
          (widget.pageLayoutMode == PdfPageLayoutMode.single
                  ? _singlePageViewKey.currentState!.trackpadTransform
                  : _transformationController)
              .toScene(Offset.zero),
          velocity,
          _pdfViewerController.zoomLevel,
        );
      }
      PageStorage.maybeOf(context)?.writeState(
        context,
        _pdfViewerController.zoomLevel,
        identifier: 'zoomLevel_${widget.key}',
      );
      _previousTiledZoomLevel = _pdfViewerController.zoomLevel;
      _checkMount();
      _getTileImage();
    }
  }

  void _applyTrackpadViewport(double zoom, Offset offset) {
    if (!mounted || _pdfViewerController.pageCount == 0 || isBookmarkViewOpen) {
      _trackpadMomentum.stop();
      return;
    }
    final double oldZoom = _pdfViewerController.zoomLevel;
    _pdfViewerController._zoomLevel = zoom;
    if (widget.pageLayoutMode == PdfPageLayoutMode.continuous) {
      _pdfScrollableStateKey.currentState?.applyTrackpadViewport(zoom, offset);
    } else {
      _singlePageViewKey.currentState?.applyTrackpadViewport(zoom, offset);
    }
    if (oldZoom != zoom) {
      widget.onZoomLevelChanged?.call(PdfZoomDetails(zoom, oldZoom));
    }
  }
}
