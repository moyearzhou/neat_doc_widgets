import 'package:flutter/material.dart';

/// Visual configuration for the PDF page handle and viewport scrollbars.
///
/// Omitted values preserve the built-in appearance. The viewer retains control
/// of positioning, hit testing and drag-to-document coordinate conversion.
@immutable
class PdfScrollbarSettings {
  /// Creates optional scrollbar customizations.
  const PdfScrollbarSettings({
    this.scrollHeadSize = const Size(36, 36),
    this.scrollHeadTouchTargetSize = const Size(48, 48),
    this.scrollHeadMargin = EdgeInsets.zero,
    this.scrollHeadDecoration,
    this.thickness,
    this.minThumbLength,
    this.thumbColor,
    this.radius,
    this.padding,
    this.showHorizontalScrollbar = true,
    this.showVerticalScrollbar = true,
    this.autoHide,
    this.fadeOutDelay = const Duration(seconds: 2),
  }) : assert(
         thickness == null || (thickness > 0 && thickness < double.infinity),
       ),
       assert(
         minThumbLength == null ||
             (minThumbLength > 0 && minThumbLength < double.infinity),
       );

  /// Used by the layout code because Size/EdgeInsets getters cannot be
  /// evaluated in a const constructor's assertions.
  bool get debugIsValid =>
      scrollHeadSize.width > 0 &&
      scrollHeadSize.width.isFinite &&
      scrollHeadSize.height > 0 &&
      scrollHeadSize.height.isFinite &&
      scrollHeadTouchTargetSize.width > 0 &&
      scrollHeadTouchTargetSize.width.isFinite &&
      scrollHeadTouchTargetSize.height > 0 &&
      scrollHeadTouchTargetSize.height.isFinite &&
      scrollHeadMargin.isNonNegative &&
      scrollHeadMargin.horizontal.isFinite &&
      scrollHeadMargin.vertical.isFinite &&
      (padding == null ||
          (padding!.isNonNegative &&
              padding!.horizontal.isFinite &&
              padding!.vertical.isFinite)) &&
      fadeOutDelay >= Duration.zero;

  /// Visual size of the mobile page handle.
  final Size scrollHeadSize;

  /// Minimum mobile hit area; enlarged as needed to contain [scrollHeadSize].
  final Size scrollHeadTouchTargetSize;

  /// Insets of the page handle's travel area, including single-page mode.
  final EdgeInsets scrollHeadMargin;

  /// Optional replacement decoration for the built-in mobile page handle.
  final BoxDecoration? scrollHeadDecoration;

  /// Desktop scrollbar thickness (8 by default; 10 for the page handle).
  final double? thickness;

  /// Minimum desktop thumb length (50 by default; 54 for the page handle).
  final double? minThumbLength;

  /// Desktop thumb color; defaults to grey.
  final Color? thumbColor;

  /// Desktop thumb corner radius; defaults to half the thickness.
  final Radius? radius;

  /// Insets of desktop viewport scrollbars. Null preserves layout defaults.
  final EdgeInsets? padding;

  /// Whether to show the desktop horizontal viewport scrollbar.
  final bool showHorizontalScrollbar;

  /// Whether to show the desktop vertical viewport scrollbar.
  final bool showVerticalScrollbar;

  /// Whether desktop viewport scrollbars fade after inactivity.
  /// Null retains the viewer's direction-dependent behavior.
  final bool? autoHide;

  /// Delay before an auto-hiding scrollbar fades.
  final Duration fadeOutDelay;
}

/// Current state and allocated visual size of a PDF scroll thumb.
@immutable
class PdfScrollThumbDetails {
  /// Creates a description passed to [PdfScrollThumbBuilder].
  const PdfScrollThumbDetails({
    required this.axis,
    required this.size,
    required this.pageNumber,
    required this.pageCount,
    required this.isScrollHead,
    required this.isDragging,
    this.isHovered = false,
  });

  /// Direction in which this thumb moves.
  final Axis axis;

  /// Size allocated by the SDK. Custom visuals are constrained to this size.
  final Size size;

  /// Current page number, starting at one after document loading.
  final int pageNumber;

  /// Total page count.
  final int pageCount;

  /// True for the page navigation handle; false for a viewport scrollbar.
  final bool isScrollHead;

  /// Whether this thumb is being dragged.
  final bool isDragging;

  /// Whether the pointer is hovering over this thumb.
  final bool isHovered;
}

/// Builds only the thumb's visual content, optionally reusing [defaultThumb].
///
/// The SDK owns gestures and semantics. Interactive descendants of the returned
/// widget do not receive pointer events. Configure size through
/// [PdfScrollbarSettings] so the visual and drag travel remain consistent.
typedef PdfScrollThumbBuilder =
    Widget Function(
      BuildContext context,
      PdfScrollThumbDetails details,
      Widget defaultThumb,
    );
