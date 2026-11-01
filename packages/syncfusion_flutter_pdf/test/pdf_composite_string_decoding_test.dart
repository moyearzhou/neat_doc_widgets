import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/exporting/pdf_text_extractor/pdf_string_decoder.dart';

Uint8List fixture(String content, {String encoding = 'Identity-H'}) {
  String stream(String s) =>
      '<< /Length ${latin1.encode(s).length} >>\nstream\n$s\nendstream';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    stream('BT /F1 18 Tf 30 200 Td $content ET'),
    '<< /Type /Font /Subtype /Type0 /BaseFont /Test /Encoding /$encoding /DescendantFonts [6 0 R] /ToUnicode 7 0 R >>',
    '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Test /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 500 >>',
    stream(
      '/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def /CMapName /Test def /CMapType 2 def 1 begincodespacerange <0000> <FFFF> endcodespacerange 9 beginbfchar <0000> <25A1> <0041> <0041> <0042> <0042> <0141> <0043> <0142> <0044> <D800> <0045> <005C> <005C> <0073> <0073> <0043> <00660069> endbfchar endcmap CMapName currentdict /CMap defineresource pop end end',
    ),
  ];
  final bytes = BytesBuilder()..add(latin1.encode('%PDF-1.4\n'));
  final offsets = <int>[0];
  for (int i = 0; i < objects.length; i++) {
    offsets.add(bytes.length);
    bytes.add(latin1.encode('${i + 1} 0 obj\n${objects[i]}\nendobj\n'));
  }
  final xref = bytes.length;
  bytes.add(latin1.encode('xref\n0 ${offsets.length}\n0000000000 65535 f \n'));
  for (final offset in offsets.skip(1)) {
    bytes.add(
      latin1.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'),
    );
  }
  bytes.add(
    latin1.encode(
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF',
    ),
  );
  return bytes.takeBytes();
}

void main() {
  final String? originalPath = Platform.environment['PDF_CAPTIONING_FIXTURE'];
  test(
    'original captioning paper selection and search',
    () {
      final document = PdfDocument(
        inputBytes: File(originalPath!).readAsBytesSync(),
      );
      addTearDown(document.dispose);
      final extractor = PdfTextExtractor(document);
      final first = extractor.extractText(startPageIndex: 0, endPageIndex: 0);
      expect(first, contains('Visuals to Text: A Comprehensive Review'));
      expect(
        first,
        contains('Image captioning refers to automatic generation'),
      );
      expect(first, isNot(contains('□')));
      final lines = extractor.extractTextLines(
        startPageIndex: 0,
        endPageIndex: 0,
      );
      expect(lines.map((l) => l.text).join(' '), contains('descriptive texts'));
      expect(lines.map((l) => l.text).join(), isNot(contains('□')));
      expect(
        extractor.findText(
          <String>['captioning'],
          startPageIndex: 0,
          endPageIndex: 0,
        ),
        isNotEmpty,
      );
      for (int page = 0; page < document.pages.count; page++) {
        expect(
          extractor
              .extractText(startPageIndex: page, endPageIndex: page)
              .trim(),
          isNotEmpty,
        );
        expect(
          extractor.extractTextLines(startPageIndex: page, endPageIndex: page),
          isNotEmpty,
        );
      }
    },
    skip:
        originalPath == null
            ? 'Set PDF_CAPTIONING_FIXTURE; user PDF is not committed.'
            : false,
  );
  final cases = <String, (String, String)>{
    'baseline_hex': ('<00410042> Tj', 'AB'),
    'literal_single': ('(\u0000A\u0000B) Tj', 'AB'),
    'literal_array': ('[(\u0000A\u0000B)] TJ', 'AB'),
    'hex_TJ': ('[<00410042>] TJ', 'AB'),
    'escaped_encoding': ('(\u0000A\u0000B) Tj', 'AB'),
    'identity_v': ('(\u0000A\u0000B) Tj', 'AB'),
    'hex_spaces': ('<00 41 00 42> Tj', 'AB'),
    'hex_tabs': ('<0041\t0042> Tj', 'AB'),
    'octal_short': (r'(\0A\0B) Tj', 'AB'),
    'octal_full': (r'(\000A\000B) Tj', 'AB'),
    'high_cid_TJ': ('[(\u0001A\u0001B)] TJ', 'CD'),
    'high_cid_hex': ('<01410142> Tj', 'CD'),
    'surrogate_cid_hex': ('<D800> Tj', 'E'),
    'surrogate_cid_literal': ('(\u00d8\u0000) Tj', 'E'),
    'trailing_s': (r'[<00410073>] TJ', 'As'),
    'ligature': (r'[<0043>] TJ', 'fi'),
    'mixed_strings': (r'[(\000A) -10 <0042>] TJ', 'AB'),
    'odd_nibble': (r'<004100420> Tj', 'AB'),
  };
  for (final entry in cases.entries) {
    test(entry.key, () {
      final encoding =
          entry.key == 'escaped_encoding'
              ? 'Identity#2DH'
              : entry.key == 'identity_v'
              ? 'Identity-V'
              : 'Identity-H';
      final document = PdfDocument(
        inputBytes: fixture(entry.value.$1, encoding: encoding),
      );
      addTearDown(document.dispose);
      final extractor = PdfTextExtractor(document);
      expect(extractor.extractText().trim(), entry.value.$2);
      expect(
        extractor.extractTextLines().map((l) => l.text).join().trim(),
        entry.value.$2,
      );
      expect(extractor.findText(<String>[entry.value.$2]), isNotEmpty);
    });
  }
  test('literal byte syntax is decoded only once', () {
    expect(decodePdfStringBytes(r'(\0A\00B\000C)'), <int>[0, 65, 0, 66, 0, 67]);
    expect(decodePdfStringBytes(r'(\(\)\\)'), <int>[40, 41, 92]);
    expect(decodePdfStringBytes('(A\\\r\nB)'), <int>[65, 66]);
    expect(decodePdfStringBytes('<4 1\t4\n2>'), <int>[65, 66]);
  });
}
