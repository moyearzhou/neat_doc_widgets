import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/common/pdfviewer_helper.dart'
    as helper;
import 'package:syncfusion_flutter_pdfviewer/src/control/desktop_scrollbar.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/scroll_head.dart';

void main() {
  testWidgets('desktop custom geometry drags both axes to zoomed bounds', (
    tester,
  ) async {
    final controller = TransformationController(
      Matrix4.identity()..scaleByDouble(2, 2, 2, 1),
    );
    final states = <PdfScrollThumbDetails>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 240,
            child: DesktopScrollbar(
              controller: controller,
              viewportSize: const Size(300, 240),
              contentSize: const Size(1000, 2000),
              settings: const PdfScrollbarSettings(
                thickness: 12,
                minThumbLength: 40,
                padding: EdgeInsets.fromLTRB(10, 20, 14, 16),
                autoHide: false,
              ),
              thumbBuilder: (_, details, child) {
                states.add(details);
                return ColoredBox(
                  key: ValueKey(details.axis),
                  color: Colors.red,
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey(Axis.vertical))),
      const Size(12, 40),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey(Axis.horizontal))),
      const Size(41.4, 12),
    );
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey(Axis.vertical))),
    );
    await drag.moveBy(const Offset(0, 25));
    await tester.pump();
    expect(states.lastWhere((d) => d.axis == Axis.vertical).isDragging, isTrue);
    await drag.moveBy(const Offset(0, 1000));
    await drag.up();
    await tester.pump();
    expect(controller.toScene(Offset.zero).dy, closeTo(1880, .001));
    expect(
      states.lastWhere((d) => d.axis == Axis.vertical).isDragging,
      isFalse,
    );
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey(Axis.vertical))),
      const Offset(0, -1000),
    );
    await tester.pump();
    expect(controller.toScene(Offset.zero).dy, closeTo(0, .001));
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey(Axis.horizontal))),
      const Offset(1000, 0),
    );
    await tester.pump();
    expect(controller.toScene(Offset.zero).dx, closeTo(850, .001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'tiny desktop track clamps minimum length without invalid transforms',
    (tester) async {
      final controller = TransformationController();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: DesktopScrollbar(
                controller: controller,
                viewportSize: const Size(20, 20),
                contentSize: const Size(200, 200),
                settings: const PdfScrollbarSettings(
                  autoHide: false,
                  showHorizontalScrollbar: false,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('horizontal_scrollbar')), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('vertical_scrollbar')),
        const Offset(0, 100),
      );
      await tester.pump();
      expect(controller.value.storage.every((value) => value.isFinite), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'auto hide respects hover and a replacement transform controller',
    (tester) async {
      final first = TransformationController();
      final second = TransformationController();
      final active = ValueNotifier(first);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 240,
              child: ValueListenableBuilder<TransformationController>(
                valueListenable: active,
                builder:
                    (_, controller, child) => DesktopScrollbar(
                      controller: controller,
                      viewportSize: const Size(300, 240),
                      contentSize: const Size(300, 2000),
                      settings: const PdfScrollbarSettings(
                        autoHide: true,
                        fadeOutDelay: Duration(milliseconds: 50),
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
      final bar = find.byKey(const ValueKey('vertical_scrollbar'));
      double opacity() =>
          tester
              .widget<AnimatedOpacity>(
                find.descendant(
                  of: bar,
                  matching: find.byType(AnimatedOpacity),
                ),
              )
              .opacity;
      expect(opacity(), 0);
      first.value = Matrix4.identity()..translateByDouble(0, -100, 0, 1);
      await tester.pump();
      expect(opacity(), 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(bar));
      await tester.pump();
      expect(opacity(), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(opacity(), 1);
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), 0);
      active.value = second;
      await tester.pump();
      first.value = Matrix4.identity()..translateByDouble(0, -200, 0, 1);
      await tester.pump();
      expect(
        opacity(),
        0,
        reason: 'The old transform must no longer drive this scrollbar',
      );
      second.value = Matrix4.identity()..translateByDouble(0, -100, 0, 1);
      await tester.pump();
      expect(opacity(), 1);
      await tester.pumpWidget(const SizedBox());
      active.dispose();
      first.dispose();
      second.dispose();
    },
  );

  testWidgets(
    'default mobile handle retains theme colors and 36 pixel visual',
    (tester) async {
      final wasDesktop = helper.kIsDesktop;
      helper.kIsDesktop = false;
      addTearDown(() => helper.kIsDesktop = wasDesktop);
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: SfPdfViewerTheme(
            data: const SfPdfViewerThemeData(
              scrollHeadStyle: PdfScrollHeadStyle(
                backgroundColor: Colors.green,
                pageNumberTextStyle: TextStyle(color: Colors.purple),
              ),
            ),
            child: ScrollHead(
              false,
              true,
              Offset.zero,
              controller,
              false,
              PdfScrollDirection.vertical,
              false,
              PdfPageLayoutMode.continuous,
            ),
          ),
        ),
      );
      final decoration = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == Colors.green,
      );
      expect(decoration, findsOneWidget);
      expect(tester.getSize(decoration), const Size(36, 36));
      expect(tester.widget<Text>(find.text('0')).style!.color, Colors.purple);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final layout in PdfPageLayoutMode.values) {
    for (final direction in PdfScrollDirection.values) {
      testWidgets(
        'custom mobile handle $layout $direction reaches first and last page',
        (tester) async {
          final wasDesktop = helper.kIsDesktop;
          helper.kIsDesktop = false;
          addTearDown(() => helper.kIsDesktop = wasDesktop);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('syncfusion_flutter_pdfviewer'),
                (call) async {
                  switch (call.method) {
                    case 'loadPdfFromFile':
                      return '4';
                    case 'getPagesWidth':
                      return List.filled(4, 600.0);
                    case 'getPagesHeight':
                      return List.filled(4, 900.0);
                    default:
                      return null;
                  }
                },
              );
          final document = PdfDocument();
          for (var i = 0; i < 4; i++) {
            document.pages.add();
          }
          final bytes = Uint8List.fromList(document.saveSync());
          document.dispose();
          final controller = PdfViewerController();
          final states = <PdfScrollThumbDetails>[];
          await tester.pumpWidget(
            MaterialApp(
              home: SfPdfViewer.memory(
                bytes,
                controller: controller,
                pageLayoutMode: layout,
                scrollDirection: direction,
                canShowScrollStatus: false,
                canShowPaginationDialog: false,
                scrollbarSettings: const PdfScrollbarSettings(
                  scrollHeadSize: Size(62, 70),
                  scrollHeadTouchTargetSize: Size(72, 80),
                  scrollHeadMargin: EdgeInsets.fromLTRB(10, 16, 12, 18),
                ),
                scrollThumbBuilder: (_, details, defaultThumb) {
                  states.add(details);
                  return const ColoredBox(
                    key: ValueKey('custom_head'),
                    color: Colors.blue,
                  );
                },
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
          expect(controller.pageCount, 4);
          if (layout == PdfPageLayoutMode.continuous) {
            controller.zoomLevel = 2;
            await tester.pump();
            await tester.pump();
          }
          final thumb = find.byKey(const ValueKey('custom_head'));
          expect(thumb, findsOneWidget);
          expect(tester.getSize(thumb), const Size(62, 70));
          final horizontal = direction == PdfScrollDirection.horizontal;
          final drag = await tester.startGesture(tester.getCenter(thumb));
          await drag.moveBy(
            horizontal ? const Offset(30, 0) : const Offset(0, 30),
          );
          await tester.pump();
          expect(states.last.isDragging, isTrue);
          await drag.moveBy(
            horizontal ? const Offset(1500, 0) : const Offset(0, 1500),
          );
          await drag.up();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(controller.pageNumber, 4);
          expect(states.last.isDragging, isFalse);
          final rect = tester.getRect(thumb);
          if (horizontal) {
            // Hit area is 72 wide and the 62-wide visual is centered within it.
            expect(rect.right, closeTo(800 - 12 - 5, 1));
          } else {
            expect(rect.bottom, closeTo(600 - 18 - 5, 1));
          }
          await tester.dragFrom(
            tester.getCenter(thumb),
            horizontal ? const Offset(-1500, 0) : const Offset(0, -1500),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(controller.pageNumber, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 3));
          controller.dispose();
        },
      );
    }
  }
}
