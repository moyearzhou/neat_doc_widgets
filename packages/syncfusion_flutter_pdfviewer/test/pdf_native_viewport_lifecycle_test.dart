import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_view.dart';

void main() {
  testWidgets(
    'OHOS page lifecycle forwards priority and invalidation to native',
    (tester) async {
      const channel = MethodChannel('syncfusion_flutter_pdfviewer');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'loadPdfFromFile':
            return '3';
          case 'getPagesWidth':
            return List<double>.filled(3, 600);
          case 'getPagesHeight':
            return List<double>.filled(3, 900);
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final document = PdfDocument();
      for (int i = 0; i < 3; i++) {
        document.pages.add();
      }
      final bytes = Uint8List.fromList(document.saveSync());
      document.dispose();
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(home: SfPdfViewer.memory(bytes, controller: controller)),
      );
      for (int i = 0; i < 50 && controller.pageCount == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(controller.pageCount, 3);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final page = tester.state<PdfPageViewState>(
        find.byWidgetPredicate(
          (widget) => widget is PdfPageView && widget.pageIndex == 0,
        ),
      );
      List<Map<Object?, Object?>> updates() =>
          calls
              .where((call) => call.method == 'updateRenderState')
              .map((call) => call.arguments as Map<Object?, Object?>)
              .where((args) => args['index'] == 1)
              .toList();

      calls.clear();
      page.setViewportActive(true, visible: false);
      page.setViewportActive(true);
      page.setViewportActive(false);
      page.setViewportActive(false);
      await tester.pump();
      expect(updates(), hasLength(3));
      expect(updates()[0]['visible'], isFalse);
      expect(updates()[1]['visible'], isTrue);
      expect(updates()[2]['active'], isFalse);

      calls.clear();
      page.setViewportActive(true);
      page.suspendRasterization();
      page.resumeRasterization();
      await tester.pump();
      expect(updates(), hasLength(3));
      expect(updates()[0]['active'], isTrue);
      expect(updates()[1]['active'], isFalse);
      expect(updates()[1]['invalidate'], isTrue);
      expect(updates()[2]['active'], isTrue);

      calls.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(updates().last['active'], isFalse);
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.ohos}),
  );
}
