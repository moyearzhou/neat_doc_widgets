import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../../pdfviewer.dart';
import '../common/pdfviewer_helper.dart';
import '../theme/theme.dart';
import 'scroll_head_metrics.dart';

/// Page navigation handle. The parent owns its drag and tap gestures.
class ScrollHead extends StatefulWidget {
  const ScrollHead(
    this.canShowHorizontalScrollBar,
    this.canShowVerticalScrollBar,
    this.scrollHeadOffset,
    this.pdfViewerController,
    this.isMobileWebView,
    this.scrollDirection,
    this.isBookmarkViewOpen,
    this.pageLayoutMode, {
    super.key,
    this.settings = const PdfScrollbarSettings(),
    this.thumbBuilder,
    this.isDragging = false,
  });

  final bool canShowHorizontalScrollBar;
  final bool canShowVerticalScrollBar;
  final Offset scrollHeadOffset;
  final PdfViewerController pdfViewerController;
  final bool isMobileWebView;
  final PdfScrollDirection scrollDirection;
  final bool isBookmarkViewOpen;
  final PdfPageLayoutMode pageLayoutMode;
  final PdfScrollbarSettings settings;
  final PdfScrollThumbBuilder? thumbBuilder;
  final bool isDragging;

  @override
  State<ScrollHead> createState() => _ScrollHeadState();
}

class _ScrollHeadState extends State<ScrollHead> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (kIsDesktop &&
            widget.scrollDirection == PdfScrollDirection.horizontal &&
            widget.pageLayoutMode != PdfPageLayoutMode.single) {
          return Stack(
            children: <Widget>[
              if (widget.canShowVerticalScrollBar)
                _buildHandle(context, constraints.biggest, Axis.vertical),
              if (widget.canShowHorizontalScrollBar)
                _buildHandle(context, constraints.biggest, Axis.horizontal),
            ],
          );
        }
        return _buildHandle(
          context,
          constraints.biggest,
          widget.scrollDirection == PdfScrollDirection.horizontal
              ? Axis.horizontal
              : Axis.vertical,
        );
      },
    );
  }

  Widget _buildHandle(BuildContext context, Size viewport, Axis axis) {
    final ScrollHeadMetrics metrics = ScrollHeadMetrics(
      viewport,
      axis,
      widget.settings,
      desktop: kIsDesktop,
    );
    final Alignment alignment =
        axis == Axis.horizontal ? Alignment.bottomLeft : Alignment.topRight;
    final double offset = (axis == Axis.horizontal
            ? widget.scrollHeadOffset.dx
            : widget.scrollHeadOffset.dy)
        .clamp(0.0, metrics.travel);
    final Widget defaultThumb =
        kIsDesktop
            ? DecoratedBox(
              decoration: BoxDecoration(
                color: widget.settings.thumbColor ?? Colors.grey,
                borderRadius: BorderRadius.all(
                  widget.settings.radius ?? const Radius.circular(7),
                ),
              ),
            )
            : _buildMobileThumb(context, axis);
    final PdfScrollThumbDetails details = PdfScrollThumbDetails(
      axis: axis,
      size: metrics.thumbSize,
      pageNumber: widget.pdfViewerController.pageNumber,
      pageCount: widget.pdfViewerController.pageCount,
      isScrollHead: true,
      isDragging: widget.isDragging,
      isHovered: _isHovered,
    );
    return Padding(
      padding: widget.settings.scrollHeadMargin,
      child: Align(
        alignment: alignment,
        child: Container(
          margin:
              axis == Axis.horizontal
                  ? EdgeInsets.only(left: offset)
                  : EdgeInsets.only(top: offset),
          width: metrics.hitSize.width,
          height: metrics.hitSize.height,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: Semantics(
              container: true,
              excludeSemantics: true,
              button: true,
              label:
                  widget.isBookmarkViewOpen
                      ? ''
                      : widget.pdfViewerController.pageNumber.toString(),
              child: Align(
                alignment:
                    axis == Axis.horizontal
                        ? Alignment.bottomCenter
                        : Alignment.centerRight,
                child: SizedBox.fromSize(
                  size: metrics.thumbSize,
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

  Widget _buildMobileThumb(BuildContext context, Axis axis) {
    final SfPdfViewerThemeData? theme = SfPdfViewerTheme.of(context);
    final bool material3 = Theme.of(context).useMaterial3;
    final SfPdfViewerThemeData effectiveTheme =
        material3
            ? SfPdfViewerThemeDataM3(context)
            : SfPdfViewerThemeDataM2(context);
    const List<BoxShadow> boxShadows = <BoxShadow>[
      BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.14), blurRadius: 2),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.12),
        blurRadius: 2,
        offset: Offset(0, 2),
      ),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.2),
        blurRadius: 3,
        offset: Offset(0, 1),
      ),
    ];

    return DecoratedBox(
      decoration:
          widget.settings.scrollHeadDecoration ??
          BoxDecoration(
            color:
                theme?.scrollHeadStyle?.backgroundColor ??
                effectiveTheme.scrollHeadStyle?.backgroundColor,
            borderRadius:
                axis == Axis.horizontal
                    ? const BorderRadius.vertical(top: Radius.circular(36))
                    : const BorderRadius.horizontal(left: Radius.circular(36)),
            boxShadow: boxShadows,
          ),
      child: Center(
        child: Text(
          '${widget.pdfViewerController.pageNumber}',
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(
                fontSize: material3 ? 14 : 12,
                color:
                    Theme.of(context).brightness == Brightness.light
                        ? Colors.black.withValues(alpha: 0.87)
                        : Colors.white.withValues(alpha: 0.87),
              )
              .merge(theme?.scrollHeadStyle?.pageNumberTextStyle),
          semanticsLabel: widget.isBookmarkViewOpen ? '' : null,
        ),
      ),
    );
  }
}
