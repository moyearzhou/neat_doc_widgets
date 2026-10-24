import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/common/pdfviewer_helper.dart'
    as viewer_environment;
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_view.dart';
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';
import 'package:syncfusion_pdfviewer_platform_interface/src/method_channel_pdfviewer.dart';

void main() {
  testWidgets(
    'clear first extraction, replace queries, then search and navigate',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final wasDesktop = viewer_environment.kIsDesktop;
      viewer_environment.kIsDesktop = true;
      addTearDown(() => viewer_environment.kIsDesktop = wasDesktop);
      PdfViewerPlatform.instance = MethodChannelPdfViewer();
      const channel = MethodChannel('syncfusion_flutter_pdfviewer');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'loadPdfFromFile':
            return '12';
          case 'getPagesWidth':
            return List<double>.filled(12, 600);
          case 'getPagesHeight':
            return List<double>.filled(12, 900);
          case 'getPage':
            final args = call.arguments as Map;
            return Uint8List(
              (args['width'] as int) * (args['height'] as int) * 4,
            );
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final document = PdfDocument();
      for (int i = 0; i < 12; i++) {
        document.pages.add().graphics.drawString(
          'alpha beta alpha page $i',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
      }
      final bytes = Uint8List.fromList(document.saveSync());
      document.dispose();
      final controller = PdfViewerController();
      final searchFocus = FocusNode();
      addTearDown(searchFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Column(
              children: [
                TextField(focusNode: searchFocus),
                Expanded(
                  child: SfPdfViewer.memory(
                    bytes,
                    controller: controller,
                    canShowPageLoadingIndicator: false,
                    canShowScrollHead: false,
                    canShowScrollStatus: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      for (int i = 0; i < 60 && controller.pageCount == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pump();
      expect(controller.pageCount, 12);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      final firstPage = tester.state<PdfPageViewState>(
        find.byType(PdfPageView).first,
      );
      for (int i = 0; i < 100 && firstPage.canvasRenderBox == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        firstPage.canvasRenderBox,
        isNotNull,
        reason: 'A rendered PDF page must own an attached keyboard focus node',
      );
      // Cancel while the first worker is still spawning, then change repeatedly.
      late PdfTextSearchResult result;
      await tester.runAsync(() async {
        controller.searchText('alpha').clear();
        for (final query in ['alpha', 'beta', 'obsolete']) {
          controller.searchText(query).clear();
        }
        result = controller.searchText('beta');
        for (int i = 0; i < 150 && !result.isSearchCompleted; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(result.isSearchCompleted, isTrue);
      expect(result.totalInstanceCount, 12);
      expect(result.currentInstanceIndex, 1);
      result.nextInstance();
      await tester.pump();
      expect(
        result.currentInstanceIndex,
        2,
        reason: 'Only one navigation listener',
      );
      result.clear();
      await tester.pump();
      expect(result.totalInstanceCount, 0);
      expect(result.hasResult, isFalse);
      // No stale completion after clearing an already parsed document search.
      controller.searchText('alpha').clear();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(result.totalInstanceCount, 0);
      expect(result.isSearchCompleted, isFalse);
      // Caller-owned search supplies matching geometry without an SDK worker.
      final loaded = PdfDocument(inputBytes: bytes);
      final matches = PdfTextExtractor(loaded).findText(['beta']);
      loaded.dispose();
      result = controller.setTextSearchResults(
        'beta',
        matches.take(2).toList(),
        isComplete: false,
      );
      await tester.pump();
      expect(result.totalInstanceCount, 2);
      expect(result.currentInstanceIndex, 1);
      expect(result.isSearchCompleted, isFalse);
      result.nextInstance();
      controller.setTextSearchResults('beta', matches, isComplete: true);
      await tester.pump();
      expect(result.totalInstanceCount, 12);
      expect(
        result.currentInstanceIndex,
        2,
        reason: 'Appending pages preserves navigation',
      );
      expect(result.isSearchCompleted, isTrue);
      controller.jumpToPage(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      searchFocus.requestFocus();
      await tester.pump();
      expect(searchFocus.hasFocus, isTrue);
      result.clear(preserveFocus: true);
      await tester.pump();
      expect(
        searchFocus.hasFocus,
        isTrue,
        reason: 'Editing a query must not move focus back into the PDF',
      );
      result = controller.setTextSearchResults(
        'beta',
        matches,
        isComplete: true,
      );
      result.clear();
      await tester.pump();
      expect(result.totalInstanceCount, 0);
      expect(result.hasResult, isFalse);
      expect(
        searchFocus.hasFocus,
        isFalse,
        reason: 'Explicit legacy clear still returns focus to the PDF',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
