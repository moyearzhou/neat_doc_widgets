import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/annotations/pdf_annotation.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_array.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';

Uint8List fixture(double x, double y, int rotation, bool inherited) {
  final geometry =
      '/MediaBox [-100 -100 700 900] /CropBox [$x $y ${x + 400} ${y + 800}] /Rotate $rotation';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 ${inherited ? geometry : ""} >>',
    '<< /Type /Page /Parent 2 0 R ${inherited ? "" : geometry} /Resources << >> >>',
  ];
  final bytes = BytesBuilder()..add(ascii.encode('%PDF-1.4\n'));
  final offsets = [0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(bytes.length);
    bytes.add(ascii.encode('${i + 1} 0 obj\n${objects[i]}\nendobj\n'));
  }
  final xref = bytes.length;
  bytes.add(ascii.encode('xref\n0 ${offsets.length}\n0000000000 65535 f \n'));
  for (final offset in offsets.skip(1)) {
    bytes.add(ascii.encode('${offset.toString().padLeft(10, "0")} 00000 n \n'));
  }
  bytes.add(
    ascii.encode(
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
    ),
  );
  return bytes.takeBytes();
}

void check(PdfDocument document, double x, double y) {
  final page = document.pages[0];
  final annotation = page.annotations[0] as PdfTextMarkupAnnotation;
  final helper = PdfAnnotationHelper.getHelper(annotation);
  final quad = helper.dictionary!['QuadPoints'] as PdfArray;
  double value(int i) => (quad[i]! as PdfNumber).value!.toDouble();
  final rect = helper.dictionary!['Rect'] as PdfArray;
  expect((rect[0]! as PdfNumber).value, closeTo(value(0), .001));
  expect((rect[3]! as PdfNumber).value, closeTo(value(1), .001));
  expect(value(0), closeTo(30 + x, .001));
  expect(value(1), closeTo(page.size.height - 20 + y, .001));
  expect(annotation.boundsCollection[0].left, closeTo(30, .001));
  expect(annotation.boundsCollection[0].top, closeTo(20, .001));
  expect(annotation.boundsCollection, hasLength(2));
}

void main() {
  for (final origin in [
    Offset.zero,
    const Offset(10.4778, 10.4778),
    const Offset(-25, 40),
  ]) {
    for (final rotation in [0, 90, 180, 270]) {
      for (final inherited in [false, true]) {
        test(
          'markup round trip origin=$origin rotation=$rotation inherited=$inherited',
          () {
            final doc = PdfDocument(
              inputBytes: fixture(origin.dx, origin.dy, rotation, inherited),
            );
            doc.pages[0].annotations.add(
              PdfTextMarkupAnnotation(
                const Rect.fromLTWH(30, 20, 100, 10),
                'test',
                PdfColor(255, 255, 0),
                boundsCollection: [
                  const Rect.fromLTWH(30, 20, 100, 10),
                  const Rect.fromLTWH(30, 40, 80, 10),
                ],
              ),
            );
            var bytes = doc.saveSync();
            doc.dispose();
            for (var i = 0; i < 2; i++) {
              final reopened = PdfDocument(inputBytes: bytes);
              check(reopened, origin.dx, origin.dy);
              (reopened.pages[0].annotations[0] as PdfTextMarkupAnnotation)
                  .boundsCollection = [
                const Rect.fromLTWH(30, 20, 100, 10),
                const Rect.fromLTWH(30, 40, 80, 10),
              ];
              bytes = reopened.saveSync();
              reopened.dispose();
            }
          },
        );
      }
    }
  }
  final source = Platform.environment['BUG124_PDF'];
  if (source != null) {
    test('reported PDF markup save', () {
      final doc = PdfDocument(inputBytes: File(source).readAsBytesSync());
      doc.pages[0].annotations.add(
        PdfTextMarkupAnnotation(
          const Rect.fromLTWH(30, 20, 100, 10),
          'test',
          PdfColor(255, 255, 0),
          boundsCollection: [
            const Rect.fromLTWH(30, 20, 100, 10),
            const Rect.fromLTWH(30, 40, 80, 10),
          ],
        ),
      );
      doc.pages[1].annotations.add(
        PdfTextMarkupAnnotation(
          const Rect.fromLTWH(397.13037, 181.75626, 98.60013, 13.50038),
          'visual origin regression',
          PdfColor(255, 255, 0),
        ),
      );
      final bytes = doc.saveSync();
      doc.dispose();
      final reopened = PdfDocument(inputBytes: bytes);
      check(reopened, 10.4778, 10.4778);
      reopened.dispose();
      final output = Platform.environment['BUG124_OUTPUT'];
      if (output != null) File(output).writeAsBytesSync(bytes);
    });
  }
}
