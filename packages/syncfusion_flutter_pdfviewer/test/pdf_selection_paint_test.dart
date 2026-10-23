import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/common/pdfviewer_helper.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_view.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_scrollable.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdfviewer_canvas.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/single_page_view.dart';

class _CountingDocument extends PdfDocument {
  _CountingDocument(Uint8List bytes) : super(inputBytes: bytes);

  int pageReads = 0;

  @override
  PdfPageCollection get pages {
    pageReads++;
    return super.pages;
  }
}

void main() {
  testWidgets('selection repaint reads page geometry once per scan', (
    tester,
  ) async {
    final source = PdfDocument();
    source.pageSettings.size = const Size(600, 900);
    final page = source.pages.add();
    final font = PdfStandardFont(PdfFontFamily.helvetica, 10);
    for (int i = 0; i < 60; i++) {
      page.graphics.drawString(
        'Line $i contains selectable text',
        font,
        bounds: Rect.fromLTWH(20, 20 + i * 12, 400, 12),
      );
    }
    final document = _CountingDocument(Uint8List.fromList(source.saveSync()));
    source.dispose();
    final lines = PdfTextExtractor(
      document,
    ).extractTextLines(startPageIndex: 0);
    expect(lines.length, greaterThan(50));
    final first = lines.first.wordCollection.first.glyphs.first;
    final selection =
        TextSelectionHelper()
          ..mouseSelectionEnabled = true
          ..viewId = 0
          ..textLines = lines
          ..firstSelectedGlyph = first
          ..startBubbleX = first.bounds.left
          ..startBubbleY = first.bounds.bottom
          ..endBubbleX = lines[20].bounds.right + 1
          ..endBubbleY = lines[20].bounds.bottom - .01
          ..endIndex = 20;
    final controller = PdfViewerController();
    final search = PdfTextSearchResult();
    const canvasKey = ValueKey('selection-canvas');
    double viewHeight = 900;
    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => SizedBox.expand(
                child: PdfViewerCanvas(
                  canvasKey,
                  viewHeight,
                  600,
                  document,
                  0,
                  {1: PdfPageInfo(0, Size(600, viewHeight))},
                  PdfInteractionMode.selection,
                  controller,
                  false,
                  true,
                  selection,
                  null,
                  null,
                  () {},
                  () {},
                  null,
                  Colors.yellow,
                  Colors.orange,
                  search,
                  false,
                  GlobalKey<PdfScrollableState>(),
                  GlobalKey<SinglePageViewState>(),
                  null,
                  PdfScrollDirection.vertical,
                  false,
                  TextDirection.ltr,
                  false,
                  false,
                  null,
                ),
              ),
        ),
      ),
    );
    await mount();
    final render = tester.renderObject<CanvasRenderBox>(find.byKey(canvasKey));
    expect(selection.copiedText, contains('Line 20'));
    expect(selection.copiedText, isNot(contains('Line 59')));

    // Moving the endpoint forces the scan through the whole page. Repainting a
    // retained selection must not resolve the loaded page tree for every line.
    selection
      ..endBubbleX = lines.last.bounds.right + 1
      ..endBubbleY = lines.last.bounds.bottom - .01;
    document.pageReads = 0;
    render.markNeedsPaint();
    await tester.pump();
    expect(document.pageReads, 2);
    expect(selection.copiedText, contains('Line 59'));
    expect(selection.selectedTextLines.length, lines.length);
    final copied = selection.copiedText;
    final bounds = selection.globalSelectedRegion;

    document.pageReads = 0;
    render.markNeedsPaint();
    await tester.pump();
    expect(document.pageReads, 2);
    expect(selection.copiedText, copied);
    expect(selection.globalSelectedRegion, bounds);

    // Window resizing must still recompute the page-to-view transform.
    viewHeight = 450;
    await mount();
    expect(selection.heightPercentage, 2);
    expect(selection.copiedText, copied);
    expect(
      selection.globalSelectedRegion!.width,
      closeTo(bounds!.width / 2, .01),
    );

    selection.reset();
    render.markNeedsPaint();
    document.pageReads = 0;
    await tester.pump();
    expect(document.pageReads, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    search.dispose();
    document.dispose();
  });
}
