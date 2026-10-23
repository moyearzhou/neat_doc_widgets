import 'dart:math' as math;
import 'dart:ui';

/// A bounded high-DPI patch, in page coordinates. Limits apply to overscan;
/// visible pixels retain their requested density even on a large display.
class PdfDetailRegion {
  const PdfDetailRegion({required this.bounds, required this.pixelScale});

  final Rect bounds;
  final double pixelScale;

  Size get imageSize => Size(
    (bounds.width * pixelScale).ceilToDouble(),
    (bounds.height * pixelScale).ceilToDouble(),
  );

  static PdfDetailRegion plan(Rect page, Rect visible, double pixelScale) {
    final Rect area = page.intersect(visible);
    // At most twice the visible area, with at most 16MiB of extra RGBA pixels.
    final double maxArea = math.min(
      area.width * area.height * 2,
      area.width * area.height + 4 * 1024 * 1024 / (pixelScale * pixelScale),
    );
    Rect expand(double fraction) => Rect.fromLTRB(
      math.max(page.left, area.left - area.width * fraction),
      math.max(page.top, area.top - area.height * fraction),
      math.min(page.right, area.right + area.width * fraction),
      math.min(page.bottom, area.bottom + area.height * fraction),
    );
    double low = 0;
    double high = 0.5;
    for (int i = 0; i < 16; i++) {
      final double middle = (low + high) / 2;
      final Rect candidate = expand(middle);
      if (candidate.width * candidate.height <= maxArea) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return PdfDetailRegion(bounds: expand(low), pixelScale: pixelScale);
  }

  /// Start replacing a patch before its remaining runway is exhausted.
  /// Page edges need no runway. A smaller window can reuse a larger patch.
  bool covers(Rect page, Rect visible, double requiredScale) {
    if (requiredScale > pixelScale * 1.001 || !_contains(bounds, visible)) {
      return false;
    }
    final double marginX = math.min(
      visible.width * 0.1,
      math.max(0, bounds.width - visible.width) * 0.25,
    );
    final double marginY = math.min(
      visible.height * 0.1,
      math.max(0, bounds.height - visible.height) * 0.25,
    );
    final Rect runway = Rect.fromLTRB(
      math.max(page.left, visible.left - marginX),
      math.max(page.top, visible.top - marginY),
      math.min(page.right, visible.right + marginX),
      math.min(page.bottom, visible.bottom + marginY),
    );
    return _contains(bounds, runway);
  }

  static bool _contains(Rect outer, Rect inner) =>
      outer.left <= inner.left + 0.001 &&
      outer.top <= inner.top + 0.001 &&
      outer.right >= inner.right - 0.001 &&
      outer.bottom >= inner.bottom - 0.001;
}
