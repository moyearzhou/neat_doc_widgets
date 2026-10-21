import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pdf_scrollbar.dart';

/// Viewport scrollbars backed by the viewer's transformation controller.
class DesktopScrollbar extends StatefulWidget {
  const DesktopScrollbar({
    super.key,
    this.canShowHorizontalScrollbar = true,
    this.canShowVerticalScrollbar = true,
    this.canFadeHorizontalScrollbar = true,
    this.canFadeVerticalScrollbar = true,
    required this.controller,
    required this.viewportSize,
    required this.contentSize,
    this.onVerticalDragStart,
    this.onVerticalDragEnd,
    this.onVerticalDragUpdate,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.verticalScrollbarPadding = const EdgeInsets.only(right: 1),
    this.horizontalScrollbarPadding = const EdgeInsets.only(bottom: 1),
    this.settings = const PdfScrollbarSettings(),
    this.thumbBuilder,
    this.pageNumber = 0,
    this.pageCount = 0,
  });

  final TransformationController controller;
  final Size viewportSize;
  final Size contentSize;
  final bool canShowHorizontalScrollbar;
  final bool canShowVerticalScrollbar;
  final bool canFadeHorizontalScrollbar;
  final bool canFadeVerticalScrollbar;
  final EdgeInsets verticalScrollbarPadding;
  final EdgeInsets horizontalScrollbarPadding;
  final PdfScrollbarSettings settings;
  final PdfScrollThumbBuilder? thumbBuilder;
  final int pageNumber;
  final int pageCount;
  final void Function(DragStartDetails)? onVerticalDragStart;
  final void Function(DragUpdateDetails)? onVerticalDragUpdate;
  final void Function(DragEndDetails)? onVerticalDragEnd;
  final void Function(DragStartDetails)? onHorizontalDragStart;
  final void Function(DragUpdateDetails)? onHorizontalDragUpdate;
  final void Function(DragEndDetails)? onHorizontalDragEnd;

  @override
  State<DesktopScrollbar> createState() => _DesktopScrollbarState();
}

class _DesktopScrollbarState extends State<DesktopScrollbar> {
  Timer? _scrollTimer;
  Axis? _hoveredAxis;
  Axis? _draggingAxis;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(DesktopScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_isScrolling) {
      setState(() => _isScrolling = true);
    }
    _startFadeOutTimer();
  }

  void _startFadeOutTimer() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(widget.settings.fadeOutDelay, () {
      if (mounted) {
        setState(() => _isScrolling = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.settings.debugIsValid);
    return ValueListenableBuilder<Matrix4>(
      valueListenable: widget.controller,
      builder: (BuildContext context, Matrix4 matrix, Widget? child) {
        return Stack(
          children: <Widget>[
            if (widget.canShowHorizontalScrollbar &&
                widget.settings.showHorizontalScrollbar)
              _buildScrollbar(context, Axis.horizontal),
            if (widget.canShowVerticalScrollbar &&
                widget.settings.showVerticalScrollbar)
              _buildScrollbar(context, Axis.vertical),
          ],
        );
      },
    );
  }

  Widget _buildScrollbar(BuildContext context, Axis axis) {
    final bool vertical = axis == Axis.vertical;
    final double scale = widget.controller.value.getMaxScaleOnAxis();
    final double viewport =
        vertical ? widget.viewportSize.height : widget.viewportSize.width;
    final double content =
        vertical ? widget.contentSize.height : widget.contentSize.width;
    if (scale <= 0 ||
        !scale.isFinite ||
        viewport <= 0 ||
        content * scale <= viewport) {
      return const SizedBox.shrink();
    }
    final EdgeInsets padding =
        widget.settings.padding ??
        (vertical
            ? widget.verticalScrollbarPadding
            : widget.horizontalScrollbarPadding);
    final double track = math.max(
      0,
      viewport - (vertical ? padding.vertical : padding.horizontal),
    );
    final double crossSpace = math.max(
      0,
      (vertical ? widget.viewportSize.width : widget.viewportSize.height) -
          (vertical ? padding.horizontal : padding.vertical),
    );
    final double thickness = math.min(
      widget.settings.thickness ?? 8,
      crossSpace,
    );
    // Both ends must remain reachable even when the minimum thumb length exceeds
    // a tiny viewport. A zero travel has no valid drag-to-content ratio.
    final double length = math.min(
      track,
      math.max(
        widget.settings.minThumbLength ?? 50,
        track * viewport / (content * scale),
      ),
    );
    final double travel = math.max(0, track - length);
    final double contentExtent = content - viewport / scale;
    final Offset scene = widget.controller.toScene(Offset.zero);
    final double sceneOffset = vertical ? scene.dy : scene.dx;
    final double position =
        (sceneOffset / contentExtent).clamp(0.0, 1.0) * travel;
    final Size size =
        vertical ? Size(thickness, length) : Size(length, thickness);
    final bool dragging = _draggingAxis == axis;
    final bool hovered = _hoveredAxis == axis;
    final bool canFade =
        widget.settings.autoHide ??
        (vertical
            ? widget.canFadeVerticalScrollbar
            : widget.canFadeHorizontalScrollbar);
    final bool visible = !canFade || dragging || hovered || _isScrolling;
    final Widget defaultThumb = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.settings.thumbColor ?? Colors.grey,
        borderRadius: BorderRadius.all(
          widget.settings.radius ?? Radius.circular(thickness / 2),
        ),
      ),
    );
    final PdfScrollThumbDetails details = PdfScrollThumbDetails(
      axis: axis,
      size: size,
      pageNumber: widget.pageNumber,
      pageCount: widget.pageCount,
      isScrollHead: false,
      isDragging: dragging,
      isHovered: hovered,
    );
    final double hitThickness = math.min(crossSpace, thickness * 1.5);
    return Positioned(
      key: ValueKey<String>(
        vertical ? 'vertical_scrollbar' : 'horizontal_scrollbar',
      ),
      top: vertical ? padding.top + position : null,
      left: vertical ? null : padding.left + position,
      right: vertical ? padding.right : null,
      bottom: vertical ? null : padding.bottom,
      width: vertical ? hitThickness : length,
      height: vertical ? length : hitThickness,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredAxis = axis),
        onExit: (_) {
          setState(() => _hoveredAxis = null);
          _startFadeOutTimer();
        },
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart:
                  vertical
                      ? (DragStartDetails details) => _startDrag(axis, details)
                      : null,
              onHorizontalDragStart:
                  vertical
                      ? null
                      : (DragStartDetails details) => _startDrag(axis, details),
              onVerticalDragUpdate:
                  vertical
                      ? (DragUpdateDetails details) =>
                          _drag(axis, details, travel, contentExtent)
                      : null,
              onHorizontalDragUpdate:
                  vertical
                      ? null
                      : (DragUpdateDetails details) =>
                          _drag(axis, details, travel, contentExtent),
              onVerticalDragEnd:
                  vertical
                      ? (DragEndDetails details) => _endDrag(axis, details)
                      : null,
              onHorizontalDragEnd:
                  vertical
                      ? null
                      : (DragEndDetails details) => _endDrag(axis, details),
              onVerticalDragCancel:
                  vertical ? () => _endDrag(axis, DragEndDetails()) : null,
              onHorizontalDragCancel:
                  vertical ? null : () => _endDrag(axis, DragEndDetails()),
              child: Align(
                alignment:
                    vertical ? Alignment.centerRight : Alignment.bottomCenter,
                child: SizedBox.fromSize(
                  size: size,
                  child: IgnorePointer(
                    child:
                        widget.thumbBuilder?.call(
                          context,
                          details,
                          defaultThumb,
                        ) ??
                        defaultThumb,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startDrag(Axis axis, DragStartDetails details) {
    setState(() => _draggingAxis = axis);
    (axis == Axis.vertical
            ? widget.onVerticalDragStart
            : widget.onHorizontalDragStart)
        ?.call(details);
  }

  void _drag(
    Axis axis,
    DragUpdateDetails details,
    double travel,
    double extent,
  ) {
    if (travel <= 0) {
      return;
    }
    final Offset scene = widget.controller.toScene(Offset.zero);
    final double oldOffset = axis == Axis.vertical ? scene.dy : scene.dx;
    final double nextOffset = (oldOffset +
            details.primaryDelta! * extent / travel)
        .clamp(0.0, extent);
    final double delta = nextOffset - oldOffset;
    widget.controller.value =
        widget.controller.value.clone()..translateByDouble(
          axis == Axis.horizontal ? -delta : 0,
          axis == Axis.vertical ? -delta : 0,
          0,
          1,
        );
    (axis == Axis.vertical
            ? widget.onVerticalDragUpdate
            : widget.onHorizontalDragUpdate)
        ?.call(details);
  }

  void _endDrag(Axis axis, DragEndDetails details) {
    setState(() => _draggingAxis = null);
    _startFadeOutTimer();
    (axis == Axis.vertical
            ? widget.onVerticalDragEnd
            : widget.onHorizontalDragEnd)
        ?.call(details);
  }
}
