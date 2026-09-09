import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/src/annotation/text_markup.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdftextline.dart';

void main() {
  test('highlight and underline retain their selected text', () {
    final List<PdfTextLine> lines = <PdfTextLine>[
      PdfTextLine(const Rect.fromLTWH(40, 80, 120, 16), 'first', 1),
      PdfTextLine(const Rect.fromLTWH(40, 100, 120, 16), 'second', 1),
    ];

    expect(
      HighlightAnnotation(textBoundsCollection: lines).selectedText,
      'first\nsecond',
    );
    expect(
      UnderlineAnnotation(textBoundsCollection: lines).selectedText,
      'first\nsecond',
    );
  });

  test('markup geometry recovers source text from PDF glyphs', () {
    final PdfDocument source = PdfDocument();
    source.pages.add().graphics.drawString(
          'before recover this text after',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
          bounds: const Rect.fromLTWH(40, 80, 300, 24),
        );
    final List<int> bytes = source.saveSync();
    source.dispose();

    final PdfDocument document = PdfDocument(inputBytes: bytes);
    try {
      final List<TextLine> pageLines = PdfTextExtractor(document)
          .extractTextLines(startPageIndex: 0, endPageIndex: 0);
      final List<TextWord> selectedWords = pageLines
          .expand((TextLine line) => line.wordCollection)
          .where((TextWord word) =>
              word.text == 'recover' ||
              word.text == 'this' ||
              word.text == 'text')
          .toList(growable: false);
      final Rect markupRect = selectedWords.skip(1).fold(
            selectedWords.first.bounds,
            (Rect bounds, TextWord word) =>
                bounds.expandToInclude(word.bounds),
          );

      final List<PdfTextLine> restored = resolveTextMarkupLines(
        markupRects: <Rect>[markupRect],
        pageTextLines: pageLines,
        pageNumber: 1,
      );

      expect(restored.single.text, 'recover this text');
    } finally {
      document.dispose();
    }
  });
}
