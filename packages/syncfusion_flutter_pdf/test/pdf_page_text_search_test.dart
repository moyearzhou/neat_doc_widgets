import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  for (final rotation in PdfPageRotateAngle.values) {
    test('page search preserves matches and summary geometry at $rotation', () {
      final source = PdfDocument();
      source.pageSettings.rotate = rotation;
      source.pages.add();
      final page = source.pages.add();
      final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
      for (final (index, text)
          in [
            'rock middle ROCK rock',
            'spaced  rock context',
            'cross',
            'line rock',
          ].indexed) {
        page.graphics.drawString(
          text,
          font,
          bounds: Rect.fromLTWH(12, 20 + index * 25, 300, 20),
        );
      }
      final bytes = Uint8List.fromList(source.saveSync());
      source.dispose();
      for (final option in <TextSearchOption?>[
        null,
        ...TextSearchOption.values,
      ]) {
        _compare(bytes, ['rock'], 1, option: option, expectHits: true);
      }
      // Preserve the legacy cross-line result, including unsupported joins.
      _compare(bytes, ['cross line'], 1);
      _compare(bytes, ['cross\r\nline'], 1);
      _compare(bytes, ['missing'], 1);
      _compare(bytes, ['rock'], 0);
    });
  }

  test('page search preserves RTL, ligatures and cropped-page coordinates', () {
    final bytes = _encodedFixture();
    // The legacy matcher accepts this fixture's visual order. Preserve its
    // behavior instead of changing bidi matching as part of a parse reuse.
    _compare(bytes, ['גבא'], 0, expectHits: true);
    _compare(bytes, ['אבג'], 0);
    _compare(bytes, ['fi'], 0, expectHits: true);
    _compare(bytes, ['rock'], 0, expectHits: true);
    _compare(bytes, ['absent'], 0);
  });

  test(
    'shared geometry preserves standalone spaces and combined glyph slots',
    () {
      final bytes = _encodedFixture(
        extraContent:
            'BT /F1 14 Tf 30 240 Td <0072006F0063006B> Tj <0020> Tj '
            '<000400200072006F0063006B> Tj 0 -30 Td '
            '[<0004> 20 <0020> 10 <0072006F0063006B>] TJ '
            '0 -30 Td <0020> Tj <0020> Tj <0072006F0063006B> Tj ET',
      );
      for (final query in ['rock', 'fi', 'fi rock', 'rock fi', 'גבא']) {
        for (final option in <TextSearchOption?>[
          null,
          ...TextSearchOption.values,
        ]) {
          _compare(bytes, [query], 0, option: option);
        }
      }
    },
  );

  test(
    'detached index survives source disposal and preserves query options',
    () {
      final document = PdfDocument(inputBytes: _encodedFixture());
      final extractor = PdfTextExtractor(document);
      final index =
          extractor
              .searchPage(['absent'], pageIndex: 0, buildSearchIndex: true)
              .searchIndex!;
      final expected = <String, List<Object?>>{
        for (final query in ['rock', 'fi', 'גבא', 'absent'])
          query: _matches(extractor.findText([query])),
      };
      document.dispose();
      for (final query in expected.keys) {
        expect(_matches(index.findText([query])), expected[query]);
      }
      expect(index.retainedBytes, greaterThan(0));
    },
  );

  test(
    'repeated calls release page scope and preserve subsequent extraction/save',
    () {
      final bytes = _encodedFixture();
      final document = PdfDocument(inputBytes: bytes);
      addTearDown(document.dispose);
      final extractor = PdfTextExtractor(document);
      final original = extractor.extractText();
      final expected = _matches(extractor.findText(['rock']));
      for (var i = 0; i < 3; i++) {
        expect(
          _matches(extractor.searchPage(['rock'], pageIndex: 0).matches),
          expected,
        );
        expect(
          extractor.searchPage(['missing'], pageIndex: 0).matches,
          isEmpty,
        );
        expect(extractor.extractText(), original);
        expect(_matches(extractor.findText(['rock'])), expected);
      }
      expect(
        () => extractor.searchPage(['rock'], pageIndex: -1),
        throwsArgumentError,
      );
      expect(
        () => extractor.searchPage(['rock'], pageIndex: 1),
        throwsArgumentError,
      );
      final reopened = PdfDocument(inputBytes: document.saveSync());
      addTearDown(reopened.dispose);
      expect(_matches(PdfTextExtractor(reopened).findText(['rock'])), expected);
    },
  );
}

void _compare(
  Uint8List bytes,
  List<String> query,
  int page, {
  TextSearchOption? option,
  bool expectHits = false,
}) {
  // Independent documents avoid allowing one path's cached state to hide a
  // difference. This checks public matching and every line/word/glyph bound.
  final baseline = PdfDocument(inputBytes: bytes);
  final candidate = PdfDocument(inputBytes: bytes);
  try {
    final legacy = PdfTextExtractor(baseline);
    final expected = legacy.findText(
      query,
      startPageIndex: page,
      searchOption: option,
    );
    if (expectHits) {
      expect(expected, isNotEmpty);
    }
    final lines =
        expected.isEmpty
            ? <TextLine>[]
            : legacy.extractTextLines(startPageIndex: page);
    final result = PdfTextExtractor(
      candidate,
    ).searchPage(query, pageIndex: page, searchOption: option);
    expect(_matches(result.matches), _matches(expected));
    expect(_lines(result.textLines), _lines(lines));
    final cached = PdfTextExtractor(candidate).searchPage(
      List.of(query),
      pageIndex: page,
      searchOption: option,
      cachedText: result.searchText,
    );
    expect(_matches(cached.matches), _matches(expected));
    expect(_lines(cached.textLines), _lines(lines));
    // Build from an unrelated query: all later terms must use detached input,
    // even if the seed query had no matches on this page.
    final indexed = PdfTextExtractor(
      candidate,
    ).searchPage(['zzzzabsent'], pageIndex: page, buildSearchIndex: true);
    expect(indexed.searchIndex, isNotNull);
    expect(
      _matches(
        indexed.searchIndex!.findText(List.of(query), searchOption: option),
      ),
      _matches(expected),
    );
    expect(
      _lines(indexed.textLines),
      _lines(legacy.extractTextLines(startPageIndex: page)),
    );
    final withoutLines = PdfTextExtractor(candidate).searchPage(
      List.of(query),
      pageIndex: page,
      searchOption: option,
      cachedText: result.searchText,
      includeTextLines: false,
    );
    expect(_matches(withoutLines.matches), _matches(expected));
    expect(withoutLines.textLines, isEmpty);
    if (expected.isNotEmpty) {
      expect(result.searchText.mayContain(query.first), isTrue);
    }

    expect(
      result.hasText,
      legacy.extractText(startPageIndex: page).trim().isNotEmpty,
    );
  } finally {
    baseline.dispose();
    candidate.dispose();
  }
}

List<Object?> _matches(List<MatchedItem> matches) => [
  for (final m in matches) [m.pageIndex, m.text, m.bounds],
];
List<Object?> _lines(List<TextLine> lines) => [
  for (final l in lines)
    [
      l.pageIndex,
      l.text,
      l.bounds,
      [
        for (final w in l.wordCollection)
          [
            w.text,
            w.bounds,
            [
              for (final g in w.glyphs) [g.text, g.bounds],
            ],
          ],
      ],
    ],
];

Uint8List _encodedFixture({String extraContent = ''}) {
  String stream(String body, [String extra = '']) =>
      '<< $extra /Length ${ascii.encode(body).length} >>\nstream\n$body\nendstream';
  // Explicit Unicode mappings exercise the existing bidi/combined-glyph path
  // without relying on a platform font or an external PDF fixture.
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 400] /CropBox [10 10 390 390] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    stream(
      'BT /F1 14 Tf 30 330 Td <000100020003> Tj 0 -30 Td <000400200072006F0063006B00200072006F0063006B> Tj ET $extraContent',
    ),
    '<< /Type /Font /Subtype /Type0 /BaseFont /TestFont /Encoding /Identity-H /DescendantFonts [7 0 R] /ToUnicode 6 0 R >>',
    stream(
      '/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n'
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n'
      '/CMapName /TestUnicode def\n/CMapType 2 def\n'
      '1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n'
      '4 beginbfchar\n<0001> <05D0>\n<0002> <05D1>\n<0003> <05D2>\n<0004> <00660069>\nendbfchar\n'
      '1 beginbfrange\n<0020> <007E> <0020>\nendbfrange\n'
      'endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend',
    ),
    '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /TestFont /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 8 0 R /DW 500 /CIDToGIDMap /Identity >>',
    '<< /Type /FontDescriptor /FontName /TestFont /Flags 32 /FontBBox [0 -200 1000 900] /ItalicAngle 0 /Ascent 800 /Descent -200 /CapHeight 700 /StemV 80 >>',
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
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
    ),
  );
  return bytes.takeBytes();
}
