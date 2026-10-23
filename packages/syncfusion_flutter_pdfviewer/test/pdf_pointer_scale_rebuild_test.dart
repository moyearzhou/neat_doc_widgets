import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/common/pdfviewer_helper.dart'
    as viewer_environment;
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_view.dart';

void main() {
  final desktop = viewer_environment.kIsDesktop;
  tearDown(() {
    viewer_environment.kIsDesktop = desktop;
  });

  // The same test runs on the ordinary SDK (desktop) and the OHOS SDK.
  final platforms = TargetPlatform.values.where(
    (platform) => platform == TargetPlatform.macOS || platform.name == 'ohos',
  );
  for (final platform in platforms) {
    for (final layout in PdfPageLayoutMode.values) {
      testWidgets(
        '${platform.name} $layout pointer scaling keeps page widgets',
        (tester) async {
          viewer_environment.kIsDesktop = platform.name != 'ohos';
          tester.view.physicalSize = const Size(1200, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
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
              case 'getPage':
                final args = call.arguments as Map;
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
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 3));
            controller.dispose();
          });
          await tester.pumpWidget(
            MaterialApp(
              home: SfPdfViewer.memory(
                bytes,
                controller: controller,
                pageLayoutMode: layout,
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
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          for (int i = 0; i < 50; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
            if (tester
                    .state<PdfPageViewState>(find.byType(PdfPageView).first)
                    .rasterBytes >
                0) {
              break;
            }
          }

          final pagesBefore = <int, PdfPageView>{
            for (final element in find.byType(PdfPageView).evaluate())
              (element.widget as PdfPageView).pageIndex:
                  element.widget as PdfPageView,
          };
          expect(pagesBefore, isNotEmpty);
          InteractiveViewer surface() => tester.widget<InteractiveViewer>(
            find.byType(InteractiveViewer).first,
          );
          void expectPagesRetained() {
            for (final element in find.byType(PdfPageView).evaluate()) {
              final page = element.widget as PdfPageView;
              expect(
                page,
                same(pagesBefore[page.pageIndex]),
                reason: 'A pointer gate change must not rebuild document pages',
              );
            }
          }

          expect(surface().scaleEnabled, isFalse);
          final position = tester.getCenter(find.byType(SfPdfViewer));
          final gesture = await tester.startGesture(position);
          await gesture.moveBy(const Offset(0, -30));
          await tester.pump();
          expect(surface().scaleEnabled, isTrue);
          expectPagesRetained();

          await gesture.up();
          await tester.pump();
          expect(surface().scaleEnabled, isFalse);
          expectPagesRetained();
          tester.binding.handlePointerEvent(
            PointerScrollEvent(
              position: position,
              scrollDelta: const Offset(0, -20),
            ),
          );
          await tester.pump();
          expect(
            controller.zoomLevel,
            1,
            reason: 'Mouse wheel scrolling must not become zoom after touch',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
        },
        variant: TargetPlatformVariant(<TargetPlatform>{platform}),
      );
    }
  }
}
