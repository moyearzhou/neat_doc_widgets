import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_raster_queue.dart';

void main() {
  test('prefetch reserves a slot for a newly visible page', () async {
    final queue = PdfRasterQueue();
    addTearDown(queue.dispose);
    final native = Completer<Uint8List?>();
    final started = <int>[];
    final first = queue.render(
      () {
        started.add(1);
        return native.future;
      },
      () => true,
      isVisible: () => false,
    );
    final next = queue.render(
      () async {
        started.add(2);
        return null;
      },
      () => true,
      isVisible: () => false,
    );
    expect(started, <int>[1]);
    final visible = queue.render(() async {
      started.add(3);
      return null;
    }, () => true);
    await visible;
    expect(started, <int>[1, 3]);
    native.complete(null);
    await first;
    await next;
    expect(started, <int>[1, 3, 2]);
  });

  test(
    'queued neighbor promoted to visible jumps ahead of older prefetch',
    () async {
      final queue = PdfRasterQueue(maxConcurrent: 1);
      addTearDown(queue.dispose);
      final native = Completer<Uint8List?>();
      final started = <int>[];
      bool entered = false;
      final first = queue.render(() => native.future, () => true);
      final older = queue.render(
        () async {
          started.add(2);
          return null;
        },
        () => true,
        isVisible: () => false,
      );
      final promoted = queue.render(
        () async {
          started.add(3);
          return null;
        },
        () => true,
        isVisible: () => entered,
      );
      entered = true;
      native.complete(null);
      await first;
      await promoted;
      await older;
      expect(started, <int>[3, 2]);
    },
  );

  test(
    'offscreen work keeps native slot and skips obsolete queued pages',
    () async {
      final queue = PdfRasterQueue(maxConcurrent: 1);
      addTearDown(queue.dispose);
      final native = Completer<Uint8List?>();
      final started = <int>[];
      bool oldVisible = true;
      final old = queue.render(() {
        started.add(1);
        return native.future;
      }, () => oldVisible);
      final skipped = queue.render(() async {
        started.add(2);
        return null;
      }, () => oldVisible);
      oldVisible = false;
      queue.discardStale();
      expect(await skipped, isNull);
      final latest = queue.render(() async {
        started.add(40);
        return Uint8List(4);
      }, () => true);
      expect(started, <int>[1]);
      native.complete(Uint8List(4));
      expect(await old, isNull);
      expect(await latest, hasLength(4));
      expect(started, <int>[1, 40]);
    },
  );

  test('render failures release the slot for the next visible page', () async {
    final queue = PdfRasterQueue(maxConcurrent: 1);
    addTearDown(queue.dispose);
    final failed = queue.render(
      () async => throw StateError('native failure'),
      () => true,
    );
    final next = queue.render(() async => Uint8List(4), () => true);
    await expectLater(failed, throwsStateError);
    expect(await next, hasLength(4));
  });

  test('disposed viewer never dispatches queued or new native work', () async {
    final queue = PdfRasterQueue(maxConcurrent: 1);
    final native = Completer<Uint8List?>();
    final first = queue.render(() => native.future, () => true);
    bool queuedStarted = false;
    final queued = queue.render(() async {
      queuedStarted = true;
      return null;
    }, () => true);
    queue.dispose();
    expect(await queued, isNull);
    expect(
      await queue.render(() async {
        queuedStarted = true;
        return null;
      }, () => true),
      isNull,
    );
    native.complete(Uint8List(4));
    expect(await first, isNull);
    expect(queuedStarted, isFalse);
  });
}
