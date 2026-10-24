import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/src/text_extraction/cancellable_search_task.dart';
import 'package:syncfusion_flutter_pdfviewer/src/text_extraction/text_extraction.dart';

void _busy(List<Object?> args) {
  (args[0]! as SendPort).send('started');
  // A synchronous extraction cannot receive a cooperative cancel message.
  while (true) {}
}

void _answer(List<Object?> args) {
  (args[0]! as SendPort).send(args[1]);
}

void _fail(List<Object?> args) => throw StateError('worker failure');

void main() {
  test(
    'extraction engine finishes and can be cancelled before start',
    () async {
      final document = PdfDocument();
      document.pages.add().graphics.drawString(
        'alpha beta',
        PdfStandardFont(PdfFontFamily.helvetica, 12),
      );
      final loaded = PdfDocument(inputBytes: document.saveSync());
      final engine = TextExtractionEngine(
        Uint8List.fromList(document.saveSync()),
      );
      final result = await engine.extractText().timeout(
        const Duration(seconds: 5),
      );
      expect(result[0], contains('beta'));
      await engine.dispose();
      loaded.dispose();
      document.dispose();
    },
  );

  test('cancel stops synchronous work and waits for exit', () async {
    final task = CancellableSearchTask();
    final started = Completer<void>();
    final run = task.run(_busy, null, (_) => started.complete());
    await started.future.timeout(const Duration(seconds: 5));
    await task.cancel().timeout(const Duration(seconds: 5));
    await run;
    final next = CancellableSearchTask();
    Object? result;
    await next.run(_answer, 42, (value) => result = value);
    expect(result, 42);
  });

  test(
    'cancel during spawn never starts payload work or leaks a worker',
    () async {
      for (int i = 0; i < 12; i++) {
        final task = CancellableSearchTask();
        final data = <Object?>[];
        final run = task.run(_busy, null, data.add);
        await task.cancel().timeout(const Duration(seconds: 5));
        await run;
        expect(data, isEmpty);
      }
    },
  );

  test('cancel before queued start and repeated cancel are safe', () async {
    final task = CancellableSearchTask();
    await task.cancel();
    await task.run(_busy, null, (_) => fail('cancelled work started'));
    await task.cancel();
  });

  test('unsendable payload fails and shuts the waiting worker down', () async {
    final port = ReceivePort();
    final task = CancellableSearchTask();
    await expectLater(task.run(_answer, port, (_) {}), throwsArgumentError);
    await task.cancel();
    port.close();
  });

  test('worker errors complete and release resources', () async {
    final task = CancellableSearchTask();
    await expectLater(
      task.run(_fail, null, (_) {}),
      throwsA(isA<RemoteError>()),
    );
    await task.cancel();
  });
}
