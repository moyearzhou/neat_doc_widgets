import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_detail_region.dart';

void main() {
  const page = Rect.fromLTWH(0, 0, 600, 2400);
  const visible = Rect.fromLTWH(0, 600, 600, 300);

  test('detail overscan covers a same-page scroll before new pixels enter', () {
    final region = PdfDetailRegion.plan(page, visible, 3);
    expect(region.bounds.top, lessThan(visible.top));
    expect(region.bounds.bottom, greaterThan(visible.bottom));
    expect(region.covers(page, visible.shift(const Offset(0, 40)), 3), isTrue);
    expect(
      region.covers(page, visible.shift(const Offset(0, 280)), 3),
      isFalse,
    );
  });

  test('runway triggers refresh before the viewport reaches a detail edge', () {
    final region = PdfDetailRegion.plan(page, visible, 3);
    final nearEdge = visible.shift(
      Offset(0, region.bounds.bottom - visible.bottom - 1),
    );
    expect(
      region.bounds.contains(nearEdge.bottomRight - const Offset(1, 1)),
      isTrue,
    );
    expect(region.covers(page, nearEdge, 3), isFalse);
  });

  test(
    'overscan respects physical-pixel allowance at high display density',
    () {
      for (final scale in <double>[1, 2, 4, 8]) {
        final region = PdfDetailRegion.plan(page, visible, scale);
        final area = region.bounds.width * region.bounds.height;
        final visibleArea = visible.width * visible.height;
        expect(area, lessThanOrEqualTo(visibleArea * 2 + 0.01));
        expect(
          (area - visibleArea) * scale * scale * 4,
          lessThanOrEqualTo(16 * 1024 * 1024 + 1),
        );
        expect(
          region.pixelScale,
          scale,
          reason: 'Do not blur visible pixels to fit overscan',
        );
      }
    },
  );

  test('window shrink reuses detail but growth or higher DPR refreshes it', () {
    final region = PdfDetailRegion.plan(page, visible, 3);
    expect(
      region.covers(page, const Rect.fromLTWH(50, 650, 450, 200), 3),
      isTrue,
    );
    expect(region.covers(page, visible, 4), isFalse);
    expect(
      region.covers(page, const Rect.fromLTWH(0, 600, 600, 800), 3),
      isFalse,
    );
  });

  test(
    'page edges and rotated horizontal bounds do not request outside pixels',
    () {
      const rotated = Rect.fromLTWH(0, 0, 2400, 600);
      const corner = Rect.fromLTWH(0, 0, 400, 600);
      final region = PdfDetailRegion.plan(rotated, corner, 2);
      expect(region.bounds.left, 0);
      expect(region.bounds.top, 0);
      expect(region.bounds.bottom, rotated.bottom);
      expect(region.bounds.right, greaterThan(corner.right));
      expect(region.covers(rotated, corner, 2), isTrue);
    },
  );
}
