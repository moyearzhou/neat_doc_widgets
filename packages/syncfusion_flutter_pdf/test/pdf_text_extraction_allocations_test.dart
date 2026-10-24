import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/exporting/pdf_text_extractor/font_structure.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/exporting/pdf_text_extractor/matrix_helper.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';

void main() {
  test('literal decoding preserves legacy octal and non-octal behavior', () {
    FontStructure font() =>
        FontStructure(PdfDictionary())
          ..characterMapTable = <double, String>{65: 'A'}
          ..differencesDictionary = <String, String?>{};
    for (final entry
        in <String, String>{
          'plain': 'plain',
          r'line\nnext': 'line\nnext',
          r'\(rock\)': r'\(rock\)',
          r'\101\102\103': 'ABC',
          r'bad\xtext': 'badxt',
          r'\12': '12',
          r'\129': '\n',
          r'\999': '999',
        }.entries) {
      expect(font().getLiteralString(entry.key, []), entry.value);
    }
    final codes = <dynamic>[];
    expect(font().getLiteralString(r'\101\102\103', codes), 'ABC');
    expect(codes, [65, 66, 67]);
    // Invalid-input behavior is intentionally retained by this optimization.
    expect(() => font().getLiteralString(r'\888', []), throwsFormatException);
    expect(() => font().getLiteralString(r'end\', []), throwsRangeError);
  });

  test(
    'direct glyph normalization matches scale/translate for affine inputs',
    () {
      final legacy =
          MatrixHelper.identity.clone()
            ..scale(0.01, 0.01, 0, 0)
            ..translate(0, 1);
      final direct = MatrixHelper(0.01, 0, 0, 0.01, 0, 1);
      for (final input in [
        MatrixHelper.identity,
        MatrixHelper(0, 2, -3, 0, 4, -5),
        MatrixHelper(-1, 0, 0, 1.5, 22, 30),
      ]) {
        final expected = legacy * input;
        final actual = direct * input;
        for (final point in [Offset.zero, const Offset(12.5, -33)]) {
          expect(actual.transform(point), expected.transform(point));
        }
        expect(actual.type, expected.type);
      }
    },
  );
}
