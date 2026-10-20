import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

// A two-page PDF with a named destination, independent of the SDK's writer.
Uint8List _fixture(
  String target, {
  bool action = false,
  bool indirect = false,
}) {
  final namedTarget = indirect ? '7 0 R' : target;
  final bookmarkTarget =
      action ? '/A << /S /GoTo /D (chapter) >>' : '/Dest (chapter)';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R /Outlines 5 0 R /Names << /Dests << /Names [(chapter) $namedTarget] >> >> >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 800] /Resources << >> >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 800] /Resources << >> >>',
    '<< /Type /Outlines /First 6 0 R /Last 6 0 R /Count 1 >>',
    '<< /Title (Chapter) /Parent 5 0 R $bookmarkTarget >>',
    if (indirect) target,
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

void _expectDestination(
  PdfDocument document,
  PdfDestinationMode mode,
  Offset location,
) {
  final named = document.bookmarks[0].namedDestination;
  expect(named?.title, 'chapter');
  final destination = named?.destination;
  expect(destination, isNotNull);
  expect(document.pages.indexOf(destination!.page), 1);
  expect(destination.mode, mode);
  expect(destination.location.dx, closeTo(location.dx, 0.001));
  expect(destination.location.dy, closeTo(location.dy, 0.001));
}

void main() {
  for (final action in [false, true]) {
    for (final indirect in [false, true]) {
      test(
        'named FitR resolves and survives save: action=$action indirect=$indirect',
        () {
          final document = PdfDocument(
            inputBytes: _fixture(
              '[4 0 R /FitR 40.5 100 220 650.25]',
              action: action,
              indirect: indirect,
            ),
          );
          addTearDown(document.dispose);
          _expectDestination(
            document,
            PdfDestinationMode.fitR,
            const Offset(40.5, 149.75),
          );
          final reopened = PdfDocument(inputBytes: document.saveSync());
          addTearDown(reopened.dispose);
          _expectDestination(
            reopened,
            PdfDestinationMode.fitR,
            const Offset(40.5, 149.75),
          );
        },
      );
    }
  }

  for (final entry
      in <String, (PdfDestinationMode, Offset)>{
        '[4 0 R /XYZ 24.5 650.25 1.5]': (
          PdfDestinationMode.location,
          const Offset(24.5, 149.75),
        ),
        '[4 0 R /FitH 650.25]': (
          PdfDestinationMode.fitH,
          const Offset(0, 149.75),
        ),
        '[4 0 R /FitBH 650.25]': (
          PdfDestinationMode.fitH,
          const Offset(0, 149.75),
        ),
        '[4 0 R /Fit]': (PdfDestinationMode.fitToPage, Offset.zero),
      }.entries) {
    test('existing named destination ${entry.key}', () {
      final document = PdfDocument(inputBytes: _fixture(entry.key));
      addTearDown(document.dispose);
      _expectDestination(document, entry.value.$1, entry.value.$2);
    });
  }

  for (final target in [
    '[4 0 R /FitR 40 100 220]',
    '[4 0 R /FitR 40 100 220 null]',
    '[4 0 R /FitR (bad) 100 220 650]',
  ]) {
    test('malformed FitR stays non-navigable: $target', () {
      final document = PdfDocument(inputBytes: _fixture(target));
      addTearDown(document.dispose);
      expect(document.bookmarks[0].namedDestination?.destination, isNull);
    });
  }

  const original = String.fromEnvironment('FITR_PDF_FIXTURE');
  test(
    'all 23 bookmarks in the reported PDF resolve to their known pages',
    () {
      final document = PdfDocument(
        inputBytes: File(original).readAsBytesSync(),
      );
      addTearDown(document.dispose);
      final pages = <int>[];
      void collect(PdfBookmarkBase root) {
        for (var i = 0; i < root.count; i++) {
          final bookmark = root[i];
          final destination =
              bookmark.namedDestination?.destination ?? bookmark.destination;
          expect(destination, isNotNull, reason: bookmark.title);
          expect(destination!.mode, PdfDestinationMode.fitR);
          expect(destination.location.isFinite, isTrue);
          pages.add(document.pages.indexOf(destination.page) + 1);
          collect(bookmark);
        }
      }

      collect(document.bookmarks);
      expect(document.pages.count, 13);
      expect(pages, [
        1,
        1,
        2,
        2,
        2,
        6,
        6,
        7,
        9,
        9,
        9,
        10,
        10,
        11,
        11,
        11,
        11,
        11,
        12,
        13,
        13,
        13,
        13,
      ]);
    },
    skip:
        original.isEmpty
            ? 'Provide FITR_PDF_FIXTURE locally; no user PDF is committed.'
            : false,
  );
}
