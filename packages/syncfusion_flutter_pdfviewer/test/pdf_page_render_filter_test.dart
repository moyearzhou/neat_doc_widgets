import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_render_surface.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_view.dart';

const _invert = ColorFilter.matrix(<double>[
  -1,
  0,
  0,
  0,
  255,
  0,
  -1,
  0,
  0,
  255,
  0,
  0,
  -1,
  0,
  255,
  0,
  0,
  0,
  1,
  0,
]);
const _capture = ValueKey('capture');
const _canvas = Color(0xFF1A237E);

Future<Color> _pixel(WidgetTester tester, Offset global) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  final local = boundary.globalToLocal(global);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final pixels = await image.toByteData();
    final offset = (local.dy.floor() * image.width + local.dx.floor()) * 4;
    final color = Color.fromARGB(
      pixels!.getUint8(offset + 3),
      pixels.getUint8(offset),
      pixels.getUint8(offset + 1),
      pixels.getUint8(offset + 2),
    );
    image.dispose();
    return color;
  }))!;
}

void main() {
  testWidgets(
    'page filter changes base and tile together but leaves surrounding chrome intact',
    (tester) async {
      final filter = ValueNotifier<ColorFilter?>(_invert);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: _capture,
              child: SizedBox(
                width: 120,
                height: 120,
                child: ColoredBox(
                  color: _canvas,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        width: 100,
                        height: 100,
                        child: ValueListenableBuilder<ColorFilter?>(
                          valueListenable: filter,
                          builder:
                              (_, value, child) => PdfPageRenderSurface(
                                colorFilter: value,
                                child: const Stack(
                                  children: [
                                    Positioned.fill(
                                      child: ColoredBox(color: Colors.white),
                                    ),
                                    Positioned(
                                      left: 40,
                                      top: 40,
                                      width: 30,
                                      height: 30,
                                      child: ColoredBox(color: Colors.black),
                                    ),
                                  ],
                                ),
                              ),
                        ),
                      ),
                      const Positioned(
                        left: 80,
                        top: 0,
                        width: 8,
                        height: 30,
                        child: ColoredBox(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byKey(_capture));
      expect(await _pixel(tester, origin + const Offset(10, 10)), Colors.black);
      expect(await _pixel(tester, origin + const Offset(50, 50)), Colors.white);
      expect(await _pixel(tester, origin + const Offset(10, 110)), _canvas);
      expect(
        await _pixel(tester, origin + const Offset(84, 10)),
        const Color(0xFF9E9E9E),
      );
      filter.value = null;
      await tester.pump();
      expect(await _pixel(tester, origin + const Offset(10, 10)), Colors.white);
      expect(await _pixel(tester, origin + const Offset(50, 50)), Colors.black);
      await tester.pumpWidget(const SizedBox());
      filter.dispose();
    },
  );

  for (final layout in PdfPageLayoutMode.values) {
    for (final direction in PdfScrollDirection.values) {
      testWidgets(
        '$layout $direction filters paper and native rasters without filtering gaps',
        (tester) async {
          final filter = ValueNotifier<ColorFilter?>(_invert);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('syncfusion_flutter_pdfviewer'),
                (call) async {
                  switch (call.method) {
                    case 'loadPdfFromFile':
                      return '2';
                    case 'getPagesWidth':
                      return [200.0, 200.0];
                    case 'getPagesHeight':
                      return [200.0, 200.0];
                    case 'getTileImage':
                      final args = call.arguments as Map;
                      final count =
                          (args['width'] as num).toInt() *
                          (args['height'] as num).toInt();
                      final pixels = Uint8List(count * 4);
                      for (var i = 3; i < pixels.length; i += 4) {
                        pixels[i] = 255;
                      }
                      return pixels;
                    case 'getPage':
                      final args = call.arguments as Map;
                      final width = (args['width'] as num).toInt();
                      final height = (args['height'] as num).toInt();
                      return Uint8List(width * height * 4)
                        ..fillRange(0, width * height * 4, 255);
                    default:
                      return null;
                  }
                },
              );
          final doc = PdfDocument();
          doc.pageSettings.size = const Size(200, 200);
          doc.pages.add();
          doc.pages.add();
          final bytes = Uint8List.fromList(doc.saveSync());
          doc.dispose();
          final controller = PdfViewerController();
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: _capture,
                  child: SizedBox(
                    width: 400,
                    height: 500,
                    child: SfPdfViewerTheme(
                      data: const SfPdfViewerThemeData(
                        backgroundColor: _canvas,
                      ),
                      child: ValueListenableBuilder<ColorFilter?>(
                        valueListenable: filter,
                        builder:
                            (_, value, child) => SfPdfViewer.memory(
                              bytes,
                              controller: controller,
                              pageLayoutMode: layout,
                              scrollDirection: direction,
                              pageRenderColorFilter: value,
                              pageSpacing: 12,
                              canShowScrollHead: false,
                              canShowScrollStatus: false,
                              canShowPageLoadingIndicator: false,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < 50 && controller.pageCount == 0; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          await tester.pump();
          expect(controller.pageCount, 2);
          final pageFinder = find.byType(PdfPageView).first;
          final page = tester.state<PdfPageViewState>(pageFinder);
          final rect = tester.getRect(pageFinder);
          final sample = rect.topLeft + const Offset(30, 30);
          expect(
            await _pixel(tester, sample),
            Colors.black,
            reason: 'An unloaded night page must not flash white',
          );
          // Explicitly request native pixels: test mode disables automatic raster timers.
          page.getPageImage(const Size(400, 500), 1);
          await tester.pump(const Duration(milliseconds: 150));
          for (
            var i = 0;
            i < 20 && find.byType(RawImage).evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(find.byType(RawImage), findsWidgets);
          expect(
            await _pixel(tester, sample),
            Colors.black,
            reason:
                'The loaded base bitmap must retain the same night paper color',
          );
          final raw =
              find
                  .descendant(of: pageFinder, matching: find.byType(RawImage))
                  .first;
          expect(
            find.ancestor(of: raw, matching: find.byType(ColorFiltered)),
            findsOneWidget,
          );
          if (layout == PdfPageLayoutMode.continuous &&
              direction == PdfScrollDirection.vertical) {
            final gap = Offset(rect.center.dx, rect.bottom - 6);
            expect(
              await _pixel(tester, gap),
              _canvas,
              reason: 'Night gap stays #1A237E instead of inverting to #E5DC81',
            );
          }
          final transform = TransformationController(
            Matrix4.identity()..scaleByDouble(2, 2, 2, 1),
          );
          await tester.runAsync(
            () => page.getTileImage(transform, const Size(400, 500), 2),
          );
          await tester.pump();
          final rasters = find.descendant(
            of: pageFinder,
            matching: find.byType(RawImage),
          );
          expect(
            rasters,
            findsNWidgets(2),
            reason: 'Exercise both the base and zoom tile raster paths',
          );
          expect(
            await _pixel(tester, sample),
            Colors.white,
            reason:
                'Opaque black native tile is inverted once, not skipped or inverted twice',
          );
          filter.value = null;
          await tester.pump();
          expect(await _pixel(tester, sample), Colors.black);
          transform.dispose();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
          controller.dispose();
          filter.dispose();
        },
      );
    }
  }
}
