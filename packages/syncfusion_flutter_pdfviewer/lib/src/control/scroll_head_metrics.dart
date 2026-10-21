import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pdf_scrollbar.dart';

/// Shared geometry for drawing and dragging the page navigation handle.
/// Travel uses the hit box, not just the visible thumb, so custom sizes and
/// margins cannot send the handle outside the viewport or truncate scrolling.
class ScrollHeadMetrics {
  ScrollHeadMetrics(
    Size viewport,
    Axis axis,
    PdfScrollbarSettings settings, {
    required bool desktop,
  }) : assert(settings.debugIsValid) {
    final EdgeInsets margin = settings.scrollHeadMargin;
    final Size available = Size(
      math.max(0, viewport.width - margin.horizontal),
      math.max(0, viewport.height - margin.vertical),
    );
    final double thickness = settings.thickness ?? 10;
    final double length = settings.minThumbLength ?? 54;
    final Size requested =
        desktop
            ? (axis == Axis.horizontal
                ? Size(length, thickness)
                : Size(thickness, length))
            : settings.scrollHeadSize;
    thumbSize = Size(
      math.min(requested.width, available.width),
      math.min(requested.height, available.height),
    );
    hitSize =
        desktop
            ? thumbSize
            : Size(
              math.min(
                available.width,
                math.max(
                  thumbSize.width,
                  settings.scrollHeadTouchTargetSize.width,
                ),
              ),
              math.min(
                available.height,
                math.max(
                  thumbSize.height,
                  settings.scrollHeadTouchTargetSize.height,
                ),
              ),
            );
    travel =
        axis == Axis.horizontal
            ? math.max(0, available.width - hitSize.width)
            : math.max(0, available.height - hitSize.height);
  }

  late final Size thumbSize;
  late final Size hitSize;
  late final double travel;
}
