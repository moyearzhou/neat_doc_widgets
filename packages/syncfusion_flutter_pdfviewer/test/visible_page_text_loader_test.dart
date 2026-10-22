import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/src/text_extraction/visible_page_text_loader.dart';

void main() {
  testWidgets('briefly visible pages never start text extraction', (
    tester,
  ) async {
    final List<int> calls = <int>[];
    final loader = VisiblePageTextLoader(
      extract: (page) async {
        calls.add(page);
        return 'page $page';
      },
      onLoaded: (_, _) {},
    );
    loader.setPages(<int>[0]);
    await tester.pump(const Duration(milliseconds: 50));
    loader.setPages(<int>[1]);
    await tester.pump(const Duration(milliseconds: 50));
    loader.setPages(<int>[8]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, <int>[8]);
    loader.dispose();
  });

  testWidgets('running page cannot publish after leaving the viewport', (
    tester,
  ) async {
    final List<int> calls = <int>[];
    final List<int> loaded = <int>[];
    final first = Completer<String?>();
    final loader = VisiblePageTextLoader(
      extract: (page) {
        calls.add(page);
        return page == 0 ? first.future : Future.value('new');
      },
      onLoaded: (page, _) => loaded.add(page),
    );
    loader.setPages(<int>[0, 1]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, <int>[0]);
    loader.setPages(<int>[9]);
    first.complete('old');
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, <int>[0, 9]);
    expect(loaded, <int>[9]);
    loader.dispose();
  });

  testWidgets('revisiting a cached page does not extract it again', (
    tester,
  ) async {
    int calls = 0;
    final loader = VisiblePageTextLoader(
      extract: (_) async {
        calls++;
        return 'text';
      },
      onLoaded: (_, _) {},
    );
    loader.setPages(<int>[0]);
    await tester.pump(const Duration(milliseconds: 200));
    loader.setPages(<int>[]);
    loader.setPages(<int>[0]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    expect(loader.textFor(0), 'text');
    loader.dispose();
  });

  testWidgets(
    'text budget evicts offscreen pages without truncating visible text',
    (tester) async {
      final loader = VisiblePageTextLoader(
        extract: (page) async => 'complete page $page',
        onLoaded: (_, _) {},
        maxCachedCharacters: 3,
      );
      loader.setPages(<int>[0]);
      await tester.pump(const Duration(milliseconds: 200));
      loader.setPages(<int>[1]);
      await tester.pump(const Duration(milliseconds: 200));
      expect(loader.textFor(0), isNull);
      expect(loader.textFor(1), 'complete page 1');
      loader.dispose();
    },
  );

  testWidgets('disposing a document ignores its late text result', (
    tester,
  ) async {
    final result = Completer<String?>();
    final List<int> loaded = <int>[];
    final loader = VisiblePageTextLoader(
      extract: (_) => result.future,
      onLoaded: (page, _) => loaded.add(page),
    );
    loader.setPages(<int>[0]);
    await tester.pump(const Duration(milliseconds: 200));
    loader.dispose();
    result.complete('old document');
    await tester.pump();
    expect(loaded, isEmpty);
  });

  test('native worker extracts original text from source bytes', () async {
    final document = PdfDocument();
    document.pages.add().graphics.drawString(
      'Accessible PDF text',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
    );
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    final worker = PageTextWorker(bytes, null);
    addTearDown(worker.dispose);
    expect(
      await worker.extract(0).timeout(const Duration(seconds: 10)),
      contains('Accessible PDF text'),
    );
    expect(
      await worker.extract(4).timeout(const Duration(seconds: 10)),
      isNull,
    );
  });
}
