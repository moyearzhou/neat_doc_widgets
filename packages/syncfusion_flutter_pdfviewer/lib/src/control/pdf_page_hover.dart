part of 'pdf_page_view.dart';

extension _PdfPageHover on PdfPageViewState {
  void _handleHover(PointerHoverEvent details) =>
      _handleHoverPosition(details.position);

  void _handleHoverPosition(Offset position) {
    _hoverPosition = position;
    _updateHoverCursor();
  }

  void _clearHover() {
    _hoverPosition = null;
    widget.hoverTextLoader?.leave(widget.pageIndex);
  }

  void _updateHoverCursor() {
    final Offset? globalPosition = _hoverPosition;
    final CanvasRenderBox? canvas = canvasRenderBox;
    if (!mounted ||
        globalPosition == null ||
        canvas == null ||
        !canvas.attached ||
        !_pageVisible ||
        widget.pdfPages.isEmpty) {
      return;
    }
    final Offset? localPosition = _globalToLocal(globalPosition);
    if (localPosition == null ||
        !(Offset.zero & Size(canvas.width, canvas.height)).contains(
          localPosition,
        ) ||
        (widget.viewportGlobalRect != null &&
            !widget.viewportGlobalRect!.contains(globalPosition))) {
      _clearHover();
      return;
    }

    final HoverTextLoader? loader = widget.hoverTextLoader;
    final bool selection = _interactionMode == PdfInteractionMode.selection;
    final HoverTextPage? text =
        selection && widget.enableTextSelection
            ? loader?.hover(widget.pageIndex, _updateHoverCursor)
            : null;
    if (loader?.isSettling ?? false) {
      _setHoverCursor(
        selection ? SystemMouseCursors.basic : SystemMouseCursors.grab,
      );
      return;
    }

    // Native hover reads prepared geometry only. Parsing a cold PDF page here
    // blocked pointer dispatch for 149–316 ms in the macOS profile capture.
    final Annotation? annotation = canvas.findAnnotation(
      localPosition,
      widget.pageIndex + 1,
    );
    final bool isLink = canvas.findTOC(localPosition);
    final SystemMouseCursor cursor;
    if (isLink) {
      cursor = SystemMouseCursors.click;
    } else if (!selection) {
      cursor = SystemMouseCursors.grab;
    } else if (annotation == null &&
        (text?.contains(localPosition, canvas.height) ?? false)) {
      cursor =
          _isRotatedTo90or270
              ? SystemMouseCursors.verticalText
              : SystemMouseCursors.text;
    } else {
      cursor = SystemMouseCursors.basic;
    }
    _setHoverCursor(cursor);
  }
}
