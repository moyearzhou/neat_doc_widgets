import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_native_render_bridge.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_raster_queue.dart';

void main() {
  for (final disposed in [false, true]) {
    test(
      'typed pixel owners release after ${disposed ? 'dispose' : 'departure'}',
      () async {
        for (int i = 0; i < 12; i++) {
          final queue = PdfRasterQueue(maxConcurrent: 1);
          final native = Completer<PdfNativePixelBuffer?>();
          int releases = 0;
          bool current = true;
          final first = queue.renderResource<PdfNativePixelBuffer>(
            () => native.future,
            () => current,
            onDiscard: (buffer) => buffer.dispose(),
          );
          final next = queue.renderResource<PdfNativePixelBuffer>(
            () async => null,
            () => true,
            onDiscard: (buffer) => buffer.dispose(),
          );
          if (disposed) {
            queue.dispose();
          } else {
            current = false;
          }
          native.complete(PdfNativePixelBuffer(Uint8List(4), () => releases++));
          expect(await first, isNull);
          expect(releases, 1);
          expect(await next, isNull);
          queue.dispose();
        }
      },
    );
  }
  for (final dispose in [false, true]) {
    test(
      'native resource is released when ${dispose ? 'disposed' : 'stale'}',
      () async {
        final queue = PdfRasterQueue(maxConcurrent: 1);
        final native = Completer<Object?>();
        final resource = Object();
        final discarded = <Object>[];
        bool current = true;
        final first = queue.renderResource<Object>(
          () => native.future,
          () => current,
          onDiscard: discarded.add,
        );
        if (dispose) {
          queue.dispose();
        } else {
          current = false;
        }
        native.complete(resource);
        expect(await first, isNull);
        expect(discarded, [same(resource)]);
        queue.dispose();
      },
    );
  }
  test('current native resource transfers ownership to the decoder', () async {
    final queue = PdfRasterQueue();
    final resource = Object();
    final discarded = <Object>[];
    expect(
      await queue.renderResource<Object>(
        () async => resource,
        () => true,
        onDiscard: discarded.add,
      ),
      same(resource),
    );
    expect(discarded, isEmpty);
    queue.dispose();
    expect(discarded, isEmpty);
  });

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
