import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/exporting/pdf_text_extractor/page_resource_loader.dart';

Uint8List _fixture({
  bool escapedDictionary = false,
  bool escapedOperand = false,
}) {
  String dictionaryName(String name) =>
      escapedDictionary ? name.replaceAll('-', '#2d') : name;
  String operandName(String name) =>
      escapedOperand ? name.replaceAll('-', '#2D') : name;
  String stream(String body, String dictionary) =>
      '<< $dictionary /Length ${ascii.encode(body).length} >>\nstream\n$body\nendstream';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 400] /Resources << /XObject << /${dictionaryName('Outer-1')} 6 0 R >> >> /Contents 4 0 R >>',
    stream('q /${operandName('Outer-1')} Do Q', ''),
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    stream(
      'q /${operandName('Inner-1')} Do Q',
      '/Type /XObject /Subtype /Form /BBox [0 0 400 400] '
          '/Resources << /XObject << /${dictionaryName('Inner-1')} 7 0 R >> >>',
    ),
    stream(
      'BT /${operandName('Font-1')} 14 Tf 30 330 Td (Hello PDF) Tj ET',
      '/Type /XObject /Subtype /Form /BBox [0 0 400 400] '
          '/Resources << /Font << /${dictionaryName('Font-1')} 5 0 R >> >>',
    ),
  ];
  final bytes = BytesBuilder()..add(ascii.encode('%PDF-1.4\n'));
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(bytes.length);
    bytes.add(ascii.encode('${i + 1} 0 obj\n${objects[i]}\nendobj\n'));
  }
  final xref = bytes.length;
  bytes.add(ascii.encode('xref\n0 ${offsets.length}\n0000000000 65535 f \n'));
  for (final offset in offsets.skip(1)) {
    bytes.add(ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'));
  }
  bytes.add(
    ascii.encode(
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n',
    ),
  );
  return bytes.takeBytes();
}

void main() {
  const cnkiFixture = String.fromEnvironment('CNKI_PDF_FIXTURE');
  test(
    'CNKI original has Chinese geometry and saves text markup',
    () {
      final document = PdfDocument(
        inputBytes: File(cnkiFixture).readAsBytesSync(),
      );
      addTearDown(document.dispose);
      final lines = PdfTextExtractor(document).extractTextLines();
      final glyphs =
          lines
              .expand((l) => l.wordCollection)
              .expand((w) => w.glyphs)
              .toList();
      final chinese = RegExp(r'[\u4e00-\u9fff]');
      expect(lines, hasLength(642));
      expect(glyphs, hasLength(18461));
      expect(glyphs.where((g) => chinese.hasMatch(g.text)), hasLength(6868));
      expect(
        glyphs.every((g) => g.bounds.isFinite && !g.bounds.isEmpty),
        isTrue,
      );
      final selected = PdfTextExtractor(document)
          .extractTextLines(startPageIndex: 0)
          .expand((l) => l.wordCollection)
          .firstWhere((w) => chinese.hasMatch(w.text));
      for (final kind in [
        PdfTextMarkupAnnotationType.highlight,
        PdfTextMarkupAnnotationType.underline,
      ]) {
        document.pages[0].annotations.add(
          PdfTextMarkupAnnotation(
            selected.bounds,
            selected.text,
            PdfColor(255, 255, 0),
            boundsCollection: [selected.bounds],
            textMarkupAnnotationType: kind,
          ),
        );
      }
      final reopened = PdfDocument(inputBytes: document.saveSync());
      addTearDown(reopened.dispose);
      final types = <PdfTextMarkupAnnotationType>[];
      for (var i = 0; i < reopened.pages[0].annotations.count; i++) {
        final a = reopened.pages[0].annotations[i];
        if (a is PdfTextMarkupAnnotation && a.text == selected.text) {
          types.add(a.textMarkupAnnotationType);
          expect(
            a.boundsCollection.single.left,
            closeTo(selected.bounds.left, 0.01),
          );
          expect(
            a.boundsCollection.single.top,
            closeTo(selected.bounds.top, 0.01),
          );
        }
      }
      expect(
        types,
        containsAll([
          PdfTextMarkupAnnotationType.highlight,
          PdfTextMarkupAnnotationType.underline,
        ]),
      );
    },
    skip:
        cnkiFixture.isEmpty
            ? 'Provide CNKI_PDF_FIXTURE locally; no user PDF is committed.'
            : false,
  );

  test('resource lookup resolves escapes once and preserves exact keys', () {
    final resources =
        PdfPageResources()
          ..add('BZ0#2D0', 'font')
          ..add('Hash#232D', 'literal hash')
          ..add('Bad#2X', 'malformed')
          ..add('Plain', 'plain');
    expect(resources.containsKey('BZ0-0'), isTrue);
    expect(resources['BZ0-0'], 'font');
    expect(resources['BZ0#2d0'], 'font');
    expect(resources['Hash#232D'], 'literal hash');
    expect(resources.containsKey('Hash#2D'), isFalse);
    expect(resources.containsKey('Hash-'), isFalse);
    expect(resources['Bad#2X'], 'malformed');
    expect(resources['Plain'], 'plain');
    expect(resources.containsKey(null), isFalse);
    expect(resources.containsKey('missing'), isFalse);
    expect(resources['missing'], isNull);
    // Resolving must not alter resource dictionaries or override exact entries.
    expect(resources.resources.length, 4);
    resources.add('BZ0-0', 'exact');
    expect(resources['BZ0-0'], 'exact');
    expect(resources['BZ0#2D0'], 'font');
  });

  for (final escapedDictionary in [false, true]) {
    for (final escapedOperand in [false, true]) {
      test(
        'nested Form geometry: dictionary=$escapedDictionary operand=$escapedOperand',
        () {
          final baseline = PdfDocument(inputBytes: _fixture());
          final document = PdfDocument(
            inputBytes: _fixture(
              escapedDictionary: escapedDictionary,
              escapedOperand: escapedOperand,
            ),
          );
          addTearDown(baseline.dispose);
          addTearDown(document.dispose);
          final expected =
              PdfTextExtractor(baseline)
                  .extractTextLines()
                  .expand((line) => line.wordCollection)
                  .expand((word) => word.glyphs)
                  .toList();
          final actual =
              PdfTextExtractor(document)
                  .extractTextLines()
                  .expand((line) => line.wordCollection)
                  .expand((word) => word.glyphs)
                  .toList();
          expect(expected.map((g) => g.text).join(), 'Hello PDF');
          expect(actual.map((g) => g.text), expected.map((g) => g.text));
          expect(actual.map((g) => g.bounds), expected.map((g) => g.bounds));
          expect(
            actual.every((g) => g.bounds.isFinite && !g.bounds.isEmpty),
            isTrue,
          );
          // The same dictionary also feeds search and plain-text extraction.
          expect(PdfTextExtractor(document).findText(['Hello']), hasLength(1));
          expect(
            PdfTextExtractor(document).extractText(),
            contains('Hello PDF'),
          );
        },
      );
    }
  }
}
