import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_view.dart';

void main() {
  testWidgets('cross-page loading indicators update without a document rebuild',
      (tester) async {
    const channel = MethodChannel('syncfusion_flutter_pdfviewer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'loadPdfFromFile':
          return '9';
        case 'getPagesWidth':
          return List<double>.filled(9, 600);
        case 'getPagesHeight':
          return List<double>.filled(9, 900);
        default:
          // Keep pages empty so indicator visibility changes remain observable.
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final document = PdfDocument();
    document.pageSettings.size = const Size(600, 900);
    for (int i = 0; i < 9; i++) {
      document.pages.add();
    }
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    final controller = PdfViewerController();
    final changedPages = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: SfPdfViewer.memory(
        bytes,
        controller: controller,
        canShowScrollHead: false,
        canShowScrollStatus: false,
        onPageChanged: (details) => changedPages.add(details.newPageNumber),
      ),
    ));
    for (int i = 0; i < 50 && controller.pageCount == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    Finder page(int number) => find.byWidgetPredicate(
          (widget) => widget is PdfPageView && widget.pageIndex == number - 1,
        );
    Finder indicator(int number) => find.descendant(
          of: page(number),
          matching: find.byType(CircularProgressIndicator),
        );
    final unrelatedPage = tester.widget<PdfPageView>(page(9));
    expect(indicator(1), findsOneWidget);
    expect(indicator(5), findsNothing);

    controller.jumpToPage(5);
    await tester.pump();
    expect(changedPages, contains(5));
    expect(indicator(1), findsNothing);
    for (final number in <int>[4, 5, 6]) {
      expect(indicator(number), findsOneWidget);
    }
    expect(tester.widget<PdfPageView>(page(9)), same(unrelatedPage));

    controller.jumpToPage(1);
    await tester.pump();
    expect(changedPages.last, 1);
    expect(indicator(1), findsOneWidget);
    expect(indicator(5), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets(
    'viewer renders both neighboring pages before they enter the viewport',
    (tester) async {
      const channel = MethodChannel('syncfusion_flutter_pdfviewer');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final rendered = <int>{};
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'loadPdfFromFile':
            return '9';
          case 'getPagesWidth':
            return List<double>.filled(9, 600);
          case 'getPagesHeight':
            return List<double>.filled(9, 900);
          case 'getPage':
            final args = call.arguments as Map;
            rendered.add(args['index'] as int);
            return Uint8List(
              (args['width'] as num).toInt() *
                  (args['height'] as num).toInt() *
                  4,
            );
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final document = PdfDocument();
      document.pageSettings.size = const Size(600, 900);
      for (int i = 0; i < 9; i++) {
        document.pages.add();
      }
      final bytes = Uint8List.fromList(document.saveSync());
      document.dispose();
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: SfPdfViewer.memory(
            bytes,
            controller: controller,
            canShowScrollHead: false,
            canShowScrollStatus: false,
          ),
        ),
      );
      for (int i = 0; i < 50 && controller.pageCount == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(controller.pageCount, 9);
      for (final element in find.byType(PdfPageView).evaluate()) {
        final boundary = element.findAncestorWidgetOfExactType<RepaintBoundary>();
        expect(boundary, isNotNull,
            reason: 'Each page must retain its own paint commands');
        expect(boundary!.child, same(element.widget),
            reason: 'The viewport boundary alone does not isolate page paints');
      }
      controller.jumpToPage(5);
      for (int frame = 0; frame < 50; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      for (final number in <int>[3, 4, 5, 6, 7]) {
        expect(
          rendered,
          contains(number),
          reason: 'Visible page 5 needs two neighbors on each side',
        );
        final page = tester.state<PdfPageViewState>(
          find.byWidgetPredicate(
            (widget) => widget is PdfPageView && widget.pageIndex == number - 1,
          ),
        );
        expect(
          page.rasterBytes,
          greaterThan(0),
          reason: 'Page $number must cache real pixels',
        );
      }
      // Changing the current page must not regenerate every page in a large
      // continuous document. Loading indicators can refresh locally instead.
      final firstPageBeforeJump = tester.widget<PdfPageView>(
        find.byWidgetPredicate(
          (widget) => widget is PdfPageView && widget.pageIndex == 0,
        ),
      );
      controller.jumpToPage(6);
      await tester.pump();
      expect(controller.pageNumber, 6);
      expect(
        tester.widget<PdfPageView>(
          find.byWidgetPredicate(
            (widget) => widget is PdfPageView && widget.pageIndex == 0,
          ),
        ),
        same(firstPageBeforeJump),
        reason: 'Crossing pages must not rebuild unrelated document pages',
      );
      final next = tester.state<PdfPageViewState>(
        find.byWidgetPredicate(
          (widget) => widget is PdfPageView && widget.pageIndex == 5,
        ),
      );
      expect(
        next.rasterBytes,
        greaterThan(0),
        reason: 'Next page must already have its preview',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'leaving and reentering a page discards stale pixels and retains native guard',
    (tester) async {
      const channel = MethodChannel('syncfusion_flutter_pdfviewer');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final requests = <Completer<Uint8List?>>[];
      final dimensions = <Size>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'loadPdfFromFile':
            return '1';
          case 'getPagesWidth':
            return [600.0];
          case 'getPagesHeight':
            return [900.0];
          case 'getPage':
            final args = call.arguments as Map;
            dimensions.add(
              Size(
                (args['width'] as num).toDouble(),
                (args['height'] as num).toDouble(),
              ),
            );
            final request = Completer<Uint8List?>();
            requests.add(request);
            return request.future;
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final document = PdfDocument();
      document.pageSettings.size = const Size(600, 900);
      document.pages.add();
      final bytes = Uint8List.fromList(document.saveSync());
      document.dispose();
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              devicePixelRatio: 4,
            ),
            child: SfPdfViewer.memory(
              bytes,
              controller: controller,
              canShowScrollHead: false,
              canShowScrollStatus: false,
            ),
          ),
        ),
      );
      for (int i = 0; i < 50 && controller.pageCount == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(controller.pageCount, 1);
      final page = tester.state<PdfPageViewState>(find.byType(PdfPageView));
      page.getPageImage(const Size(800, 600), 1);
      await tester.pump();
      expect(requests, hasLength(1));
      expect(
        dimensions.single.width * dimensions.single.height * 4,
        lessThanOrEqualTo(16 * 1024 * 1024),
      );
      page.clearPageImage();
      page.getPageImage(const Size(800, 600), 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        requests,
        hasLength(1),
        reason: 'Offscreen requests are suppressed',
      );
      page.setViewportActive(true);
      page.getPageImage(const Size(800, 600), 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        requests,
        hasLength(1),
        reason: 'Reentry must retain the running native guard',
      );
      requests.first.complete(Uint8List(0));
      await tester.pump();
      await tester.pump();
      expect(
        requests,
        hasLength(2),
        reason: 'Only the newest viewport is rendered after return',
      );
      expect(
        find.byType(RawImage),
        findsNothing,
        reason: 'The invalid stale buffer must never be decoded or installed',
      );
      requests.last.complete(null);
      await tester.pump();

      // Neighbor loading must survive the continuous stream of viewport
      // refreshes. Previously every refresh restarted its 100ms timer.
      page.clearPageImage();
      page.setViewportActive(true, visible: false);
      for (int frame = 0; frame < 10; frame++) {
        page.getPageImage(const Size(800, 600), 1);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        requests,
        hasLength(3),
        reason: 'Neighbors must render while scrolling continues',
      );
      final previewSize = dimensions.last;
      expect(previewSize.width, lessThanOrEqualTo(768));
      requests.last.complete(
        Uint8List(previewSize.width.toInt() * previewSize.height.toInt() * 4),
      );
      for (int i = 0; i < 30 && page.rasterBytes == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        page.rasterBytes,
        greaterThan(0),
        reason: 'A neighbor needs actual cached pixels before entering',
      );
      page.setViewportActive(true);
      page.getPageImage(const Size(800, 600), 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        page.rasterBytes,
        greaterThan(0),
        reason: 'Keep the preview displayed while upgrading its resolution',
      );
      expect(requests, hasLength(4));
      expect(dimensions.last.width, greaterThan(previewSize.width));
      requests.last.complete(null);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}
