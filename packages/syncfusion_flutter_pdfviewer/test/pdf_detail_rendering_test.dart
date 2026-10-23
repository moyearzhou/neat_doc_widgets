import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_page_view.dart';

class _Reader {
  _Reader({
    this.pageSize = const Size(600, 2400),
    this.direction = PdfScrollDirection.vertical,
    this.layout = PdfPageLayoutMode.continuous,
    this.initialZoom = 1,
  });

  final Size pageSize;
  final PdfScrollDirection direction;
  final PdfPageLayoutMode layout;
  final double initialZoom;
  final controller = PdfViewerController();
  final tiles = <Map<dynamic, dynamic>>[];
  final pending = <Completer<Uint8List?>>[];
  bool hold = false;
  late Uint8List bytes;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final document = PdfDocument();
    document.pageSettings.size = pageSize;
    document.pages.add();
    bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    const channel = MethodChannel('syncfusion_flutter_pdfviewer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'loadPdfFromFile':
          return '1';
        case 'getPagesWidth':
          return <double>[pageSize.width];
        case 'getPagesHeight':
          return <double>[pageSize.height];
        case 'getPage':
          return pixels(call.arguments as Map);
        case 'getTileImage':
          tiles.add(Map.of(call.arguments as Map));
          if (hold) {
            final result = Completer<Uint8List?>();
            pending.add(result);
            return result.future;
          }
          return pixels(call.arguments as Map);
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      MaterialApp(
        home: SfPdfViewer.memory(
          bytes,
          controller: controller,
          scrollDirection: direction,
          pageLayoutMode: layout,
          initialZoomLevel: initialZoom,
          maxZoomLevel: 8,
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
    expect(controller.pageCount, 1);
    await settle(tester);
    expect(tiles, isNotEmpty, reason: 'Exercise real viewer detail scheduling');
    expect(images(tester), hasLength(2));
  }

  static Uint8List pixels(Map<dynamic, dynamic> args) => Uint8List(
    (args['width'] as num).toInt() * (args['height'] as num).toInt() * 4,
  );

  List<RawImage> images(WidgetTester tester) =>
      tester
          .widgetList<RawImage>(
            find.descendant(
              of: find.byType(PdfPageView),
              matching: find.byType(RawImage),
            ),
          )
          .toList();

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    for (final request in pending) {
      if (!request.isCompleted) {
        request.complete(null);
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    controller.dispose();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  testWidgets('single-page zooming refreshes detail while retaining pixels', (
    tester,
  ) async {
    final reader = _Reader(layout: PdfPageLayoutMode.single, initialZoom: 4);
    await reader.mount(tester);
    final before = reader.tiles.length;
    reader.controller.zoomLevel = 5;
    await reader.settle(tester);
    expect(reader.tiles.length, greaterThan(before));
    expect(reader.images(tester), hasLength(2));
    expect(reader.controller.pageNumber, 1);
    await reader.dispose(tester);
  });

  testWidgets('a smaller window replaces detail with a full-density page', (
    tester,
  ) async {
    final reader = _Reader();
    await reader.mount(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 300);
    await reader.settle(tester);
    expect(reader.images(tester), hasLength(1));
    final image = reader.images(tester).single.image!;
    expect(image.width, 400);
    expect(image.height, 1600);
    await reader.dispose(tester);
  });

  testWidgets(
    'horizontal same-page scrolling reuses detail and refreshes near its edge',
    (tester) async {
      final reader = _Reader(
        pageSize: const Size(2400, 600),
        direction: PdfScrollDirection.horizontal,
      );
      await reader.mount(tester);
      reader.controller.zoomLevel = 3;
      await reader.settle(tester);
      reader.controller.jumpTo(xOffset: 200);
      await reader.settle(tester);
      expect(reader.controller.scrollOffset.dx, closeTo(200, 1));
      final count = reader.tiles.length;
      final sharp = reader.images(tester).last.image;
      reader.controller.jumpTo(xOffset: 220);
      await reader.settle(tester);
      expect(reader.tiles.length, count);
      expect(reader.images(tester).last.image, same(sharp));
      reader.controller.jumpTo(xOffset: 450);
      await reader.settle(tester);
      expect(reader.tiles.length, greaterThan(count));
      expect(
        (reader.tiles.last['x'] as num).toDouble(),
        greaterThan((reader.tiles[count - 1]['x'] as num).toDouble()),
      );
      await reader.dispose(tester);
    },
  );

  testWidgets(
    'same-page scrolling reuses sharp overscan without another render',
    (tester) async {
      final reader = _Reader();
      await reader.mount(tester);
      reader.controller.jumpTo(yOffset: 800);
      await reader.settle(tester);
      final count = reader.tiles.length;
      final sharp = reader.images(tester).last.image;
      reader.controller.jumpTo(yOffset: 850);
      await reader.settle(tester);
      expect(reader.tiles.length, count);
      expect(reader.images(tester).last.image, same(sharp));
      await reader.dispose(tester);
    },
  );

  testWidgets(
    'continuous scrolling refreshes sharp pixels before the gesture stops',
    (tester) async {
      final reader = _Reader();
      await reader.mount(tester);
      final before = reader.tiles.length;
      for (int i = 0; i < 18; i++) {
        reader.controller.jumpTo(yOffset: 50.0 * (i + 1));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(
        reader.tiles.length,
        greaterThan(before),
        reason: 'Do not debounce each move for 400ms',
      );
      await reader.dispose(tester);
    },
  );

  testWidgets(
    'an in-flight replacement retains old detail and catches up to latest offset',
    (tester) async {
      final reader = _Reader();
      await reader.mount(tester);
      final sharp = reader.images(tester).last.image;
      reader.hold = true;
      reader.controller.jumpTo(yOffset: 1000);
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pump();
      expect(reader.pending, hasLength(1));
      expect(reader.images(tester).last.image, same(sharp));
      reader.controller.jumpTo(yOffset: 2200);
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        reader.pending,
        hasLength(1),
        reason: 'Only one native detail request per page',
      );
      reader.hold = false;
      reader.pending.first.complete(_Reader.pixels(reader.tiles.last));
      await reader.settle(tester);
      expect(reader.images(tester).last.image, isNot(same(sharp)));
      final latest = reader.tiles.last;
      expect((latest['y'] as num).toDouble(), greaterThan(600));
      await reader.dispose(tester);
    },
  );

  testWidgets(
    'window and display density changes refresh pixels without dropping the base',
    (tester) async {
      final reader = _Reader();
      await reader.mount(tester);
      reader.controller.jumpTo(yOffset: 1000);
      await reader.settle(tester);
      final before = reader.tiles.length;
      final oldScale = (reader.tiles.last['scale'] as num).toDouble();
      tester.view.physicalSize = const Size(2000, 1400);
      await reader.settle(tester);
      expect(reader.tiles.length, greaterThan(before));
      expect(reader.images(tester), hasLength(2));
      expect(
        reader.controller.scrollOffset.dy,
        closeTo(1250, 2),
        reason: 'Keep the same PDF point when the fitted page width changes',
      );
      final resizedScale = (reader.tiles.last['scale'] as num).toDouble();
      expect(resizedScale, greaterThan(oldScale));
      final resizedCount = reader.tiles.length;
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(3000, 2100);
      await reader.settle(tester);
      expect(reader.tiles.length, greaterThan(resizedCount));
      expect(
        (reader.tiles.last['scale'] as num).toDouble(),
        greaterThan(resizedScale),
      );
      expect(reader.controller.pageNumber, 1);
      await reader.dispose(tester);
    },
  );
}
