import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/src/text_extraction/hover_text_loader.dart';
import 'package:syncfusion_flutter_pdfviewer/src/text_extraction/visible_page_text_loader.dart';

Float64List geometry([double height = 100]) =>
    Float64List.fromList(<double>[height, 10, 20, 30, 40]);

void main() {
  test('hover rectangles scale with displayed page height', () {
    final page = HoverTextPage(geometry());
    expect(page.contains(const Offset(40, 60), 200), isTrue);
    expect(page.contains(const Offset(60, 60), 200), isFalse);
    expect(page.contains(const Offset(40, 60), 0), isFalse);
  });

  testWidgets('brief hover never starts PDF extraction', (tester) async {
    final calls = <int>[];
    final loader = HoverTextLoader(
      extract: (page, _) async {
        calls.add(page);
        return geometry();
      },
    );
    loader.hover(0, () {});
    await tester.pump(const Duration(milliseconds: 50));
    loader.leave(0);
    loader.hover(1, () {});
    await tester.pump(const Duration(milliseconds: 50));
    loader.hover(9, () {});
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, <int>[9]);
    loader.dispose();
  });

  testWidgets('viewport changes postpone work even within the same page', (
    tester,
  ) async {
    var calls = 0;
    final loader = HoverTextLoader(
      extract: (_, _) async {
        calls++;
        return geometry();
      },
    );
    loader.hover(0, () {});
    for (var i = 0; i < 8; i++) {
      loader.viewportChanged();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    loader.dispose();
  });

  testWidgets('old extraction cannot publish or replace the new target', (
    tester,
  ) async {
    final old = Completer<Float64List?>();
    final calls = <int>[];
    final published = <int>[];
    final loader = HoverTextLoader(
      extract: (page, _) {
        calls.add(page);
        return page == 0 ? old.future : Future.value(geometry());
      },
    );
    loader.hover(0, () => published.add(0));
    await tester.pump(const Duration(milliseconds: 200));
    loader.leave(0);
    loader.hover(1, () => published.add(1));
    old.complete(geometry());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, <int>[0, 1]);
    expect(published, <int>[1]);
    expect(loader.hover(0, () {}), isNull);
    loader.dispose();
  });

  testWidgets('cached hover geometry is reused and bounded', (tester) async {
    final calls = <int>[];
    final loader = HoverTextLoader(
      maxCachedPages: 2,
      extract: (page, _) async {
        calls.add(page);
        return geometry();
      },
    );
    for (var page = 0; page < 3; page++) {
      loader.hover(page, () {});
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(loader.hover(1, () {}), isNotNull);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, <int>[0, 1, 2]);
    expect(loader.hover(0, () {}), isNull);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, <int>[0, 1, 2, 0]);
    loader.dispose();
  });

  testWidgets('failed page does not retry on every pointer movement', (
    tester,
  ) async {
    var calls = 0;
    final loader = HoverTextLoader(
      extract: (_, _) async {
        calls++;
        throw StateError('malformed page');
      },
    );
    loader.hover(0, () {});
    await tester.pump(const Duration(milliseconds: 200));
    loader.hover(0, () {});
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    loader.dispose();
  });

  testWidgets('document disposal rejects a running result', (tester) async {
    final result = Completer<Float64List?>();
    var published = false;
    final loader = HoverTextLoader(extract: (_, _) => result.future);
    loader.hover(0, () => published = true);
    await tester.pump(const Duration(milliseconds: 200));
    loader.dispose();
    result.complete(geometry());
    await tester.pump();
    expect(published, isFalse);
  });

  test(
    'shared worker serializes hover geometry and accessibility text',
    () async {
      final document = PdfDocument();
      document.pages.add().graphics.drawString(
        'Hover text',
        PdfStandardFont(PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(40, 80, 200, 30),
      );
      final bytes = Uint8List.fromList(document.saveSync());
      document.dispose();
      final expectedDocument = PdfDocument(inputBytes: bytes);
      final expected = extractHoverTextBounds(expectedDocument, 0);
      expectedDocument.dispose();
      final worker = PageTextWorker(bytes, null);
      addTearDown(worker.dispose);
      final results = await Future.wait<Object?>(<Future<Object?>>[
        worker.extractHoverBounds(0, () => true),
        worker.extract(0),
        worker.extractHoverBounds(0, () => false),
      ]).timeout(const Duration(seconds: 15));
      expect(results[0], orderedEquals(expected));
      expect(results[1], contains('Hover text'));
      expect(results[2], isNull);
    },
  );
}
