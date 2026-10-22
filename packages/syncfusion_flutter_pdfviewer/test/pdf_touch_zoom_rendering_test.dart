import 'dart:async';

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
  setUp(() => viewer_environment.kIsDesktop = false);
  tearDown(() => viewer_environment.kIsDesktop = desktop);
  for (final layout in PdfPageLayoutMode.values) {
    for (final cancel in [false, true]) {
      testWidgets(
        '$layout touch pinch retains raster; cancel=$cancel',
        (tester) async {
          const channel = MethodChannel('syncfusion_flutter_pdfviewer');
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'loadPdfFromFile':
                return '2';
              case 'getPagesWidth':
                return [600.0, 600.0];
              case 'getPagesHeight':
                return [900.0, 900.0];
              default:
                return null;
            }
          });
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
          final document = PdfDocument();
          document.pages.add();
          document.pages.add();
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
          for (var i = 0; i < 50 && controller.pageCount == 0; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(controller.pageCount, 2);
          final page = tester.state<PdfPageViewState>(
            find.byType(PdfPageView).first,
          );
          final requests = <Completer<Uint8List?>>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getPage') {
              final request = Completer<Uint8List?>();
              requests.add(request);
              return request.future;
            }
            return null;
          });
          final center = tester.getCenter(find.byType(SfPdfViewer));
          final first = await tester.startGesture(
            center - const Offset(70, 0),
            pointer: 31,
          );
          final second = await tester.startGesture(
            center + const Offset(70, 0),
            pointer: 32,
          );
          for (var i = 0; i < 4; i++) {
            await first.moveBy(const Offset(-12, 0));
            await second.moveBy(const Offset(12, 0));
            await tester.pump(const Duration(milliseconds: 16));
          }
          final transform =
              tester
                  .widgetList<InteractiveViewer>(find.byType(InteractiveViewer))
                  .first
                  .transformationController!;
          expect(transform.value.getMaxScaleOnAxis(), greaterThan(1.1));
          // Exercise the real raster entry point even if an earlier timer fires
          // during a new pinch. Widget-test viewer timers are otherwise disabled.
          page.getPageImage(const Size(800, 600), 1.3);
          await tester.pump(const Duration(milliseconds: 150));
          expect(
            requests,
            isEmpty,
            reason: 'Touch pinch must suspend native raster requests',
          );
          if (cancel) {
            await first.cancel();
            await second.cancel();
          } else {
            await first.up();
            await second.up();
          }
          await tester.pump();
          page.getPageImage(const Size(800, 600), controller.zoomLevel);
          await tester.pump(const Duration(milliseconds: 150));
          expect(
            requests,
            hasLength(1),
            reason: 'Release and cancellation must allow the final raster',
          );
          // One-finger panning must still load pages entering the viewport.
          requests.removeLast().complete(null);
          await tester.pump();
          final pan = await tester.startGesture(center, pointer: 33);
          await pan.moveBy(const Offset(0, -40));
          await pan.moveBy(const Offset(0, -40));
          page.getPageImage(const Size(800, 600), controller.zoomLevel);
          await tester.pump(const Duration(milliseconds: 150));
          expect(requests, hasLength(1));
          requests.single.complete(null);
          await pan.up();
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.ohos,
        }),
      );
    }
  }
}
