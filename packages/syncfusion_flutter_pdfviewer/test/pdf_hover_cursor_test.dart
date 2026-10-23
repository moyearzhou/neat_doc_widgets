import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/common/pdfviewer_helper.dart'
    as helper;
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_view.dart';

void main() {
  testWidgets(
    'cold hover prepares text off-thread and preserves link cursors',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final wasDesktop = helper.kIsDesktop;
      helper.kIsDesktop = true;
      addTearDown(() => helper.kIsDesktop = wasDesktop);
      const channel = MethodChannel('syncfusion_flutter_pdfviewer');
      final document = PdfDocument();
      final pdfPage = document.pages.add();
      pdfPage.graphics.drawString(
        'Hover cursor text',
        PdfStandardFont(PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(40, 80, 200, 30),
      );
      pdfPage.annotations.add(
        PdfUriAnnotation(
          bounds: const Rect.fromLTWH(40, 160, 100, 25),
          uri: 'https://example.com',
        ),
      );
      final bytes = Uint8List.fromList(document.saveSync());
      document.dispose();
      final loaded = PdfDocument(inputBytes: bytes);
      final pageSize = loaded.pages[0].size;
      final textBounds =
          PdfTextExtractor(loaded)
              .extractTextLines(startPageIndex: 0)
              .first
              .wordCollection
              .first
              .bounds;
      final linkBounds = loaded.pages[0].annotations[0].bounds;
      loaded.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'loadPdfFromFile':
                return '1';
              case 'getPagesWidth':
                return <double>[pageSize.width];
              case 'getPagesHeight':
                return <double>[pageSize.height];
              case 'getPage':
                final arguments = call.arguments as Map;
                return Uint8List(
                  (arguments['width'] as int) *
                      (arguments['height'] as int) *
                      4,
                );
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(home: SfPdfViewer.memory(bytes, controller: controller)),
      );
      for (var i = 0; i < 50 && controller.pageCount == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.pageCount, 1);
      final page = tester.state<PdfPageViewState>(find.byType(PdfPageView));
      for (var i = 0; i < 100 && page.canvasRenderBox == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(page.canvasRenderBox, isNotNull);
      expect(
        page.widget.isMobileWebView,
        isFalse,
        reason: 'The hover regression must exercise the desktop layout.',
      );
      final canvas = page.canvasRenderBox!;
      final scale = canvas.height / pageSize.height;
      final textPosition = canvas.localToGlobal(textBounds.center * scale);
      final mouseRegion = find.descendant(
        of: find.byType(PdfPageView),
        matching: find.byWidgetPredicate(
          (widget) => widget is MouseRegion && widget.onHover != null,
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(textPosition);
      await tester.pump();
      // The old implementation populated these lines synchronously on hover.
      expect(page.widget.textSelectionHelper.cursorTextLines, isNull);
      expect(
        tester.widget<MouseRegion>(mouseRegion).cursor,
        SystemMouseCursors.basic,
      );
      await tester.pump(const Duration(milliseconds: 400));
      for (
        var i = 0;
        i < 100 &&
            tester.widget<MouseRegion>(mouseRegion).cursor !=
                SystemMouseCursors.text;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        tester.widget<MouseRegion>(mouseRegion).cursor,
        SystemMouseCursors.text,
      );
      expect(page.widget.textSelectionHelper.cursorTextLines, isNull);
      await mouse.moveTo(canvas.localToGlobal(linkBounds.center * scale));
      await tester.pump();
      expect(
        tester.widget<MouseRegion>(mouseRegion).cursor,
        SystemMouseCursors.click,
      );
      await mouse.moveTo(textPosition);
      await mouse.down(textPosition);
      await tester.pump();
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.down(textPosition);
      await tester.pump();
      await mouse.up();
      await tester.pump();
      expect(
        page.widget.textSelectionHelper.textLines,
        isNotEmpty,
        reason: 'Mouse double-click must reach the text selection extractor',
      );
      expect(
        page.widget.textSelectionHelper.firstSelectedGlyph,
        isNotNull,
        reason: 'Double-click must hit a word, rather than page whitespace',
      );
      await mouse.removePointer();
      // Let the viewer's delayed tap and selection callbacks finish before disposal.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
