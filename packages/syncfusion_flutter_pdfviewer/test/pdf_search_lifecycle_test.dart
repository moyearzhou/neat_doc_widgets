import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';
import 'package:syncfusion_pdfviewer_platform_interface/src/method_channel_pdfviewer.dart';

void main() {
  testWidgets(
    'clear first extraction, replace queries, then search and navigate',
    (tester) async {
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
      await tester.pumpWidget(
        MaterialApp(
          home: SfPdfViewer.memory(
            bytes,
            controller: controller,
            canShowPageLoadingIndicator: false,
            canShowScrollHead: false,
            canShowScrollStatus: false,
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
      result.clear();
      await tester.pump();
      expect(result.totalInstanceCount, 0);
      expect(result.hasResult, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
