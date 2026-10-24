import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/exporting/pdf_text_extractor/parser/content_lexer.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/exporting/pdf_text_extractor/parser/content_parser.dart';

void main() {
  test('operator letter detection preserves original ASCII-only semantics', () {
    final lexer = ContentLexer([]);
    final oldUpper = RegExp(r'[A-Z]');
    final oldLower = RegExp(r'[a-z]');
    for (int code = 0; code <= 0xffff; code++) {
      final value = String.fromCharCode(code);
      expect(
        lexer.isLetter(value),
        oldUpper.hasMatch(value) || oldLower.hasMatch(value),
        reason: 'UTF-16 code unit $code',
      );
    }
    for (final value in ['', '123', '1T2', '/name', 'é中', '😀', '😀z']) {
      expect(
        lexer.isLetter(value),
        oldUpper.hasMatch(value) || oldLower.hasMatch(value),
      );
    }
  });

  test('content tokens preserve graphics, text, escapes and comments', () {
    final parser = ContentParser(
      ascii.encode(
        '% ignored comment\nq 1 0 0 1 12 -3.5 cm\n'
        'BT /F1 12 Tf 0.5 Tc 10 20 Td [(rock) -30 (soil)] TJ '
        r'(escaped\(text\)) Tj <726F636B> Tj ET Q',
      ),
    )..isTextExtractionProcess = true;
    final records = parser.readContent()!.recordCollection;
    expect(records.map((r) => r.operatorName), [
      'q',
      'cm',
      'BT',
      'Tf',
      'Tc',
      'Td',
      'TJ',
      'Tj',
      'Tj',
      'ET',
      'Q',
    ]);
    expect(records[1].operands, ['1', '0', '0', '1', '12', '-3.5']);
    expect(records[3].operands, ['/F1', '12']);
    expect(records[6].operands, ['[(rock) -30 (soil)]']);
  });
}
