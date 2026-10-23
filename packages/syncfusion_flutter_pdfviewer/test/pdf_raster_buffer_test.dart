import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_raster_buffer.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_raster_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('syncfusion_flutter_pdfviewer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late File file;
  late List<String> released;
  final pixels = Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]);
  Map<String, Object> metadata() => {
    'token': 'owned-token',
    'path': file.path,
    'byteLength': pixels.length,
  };

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    directory = await Directory.systemTemp.createTemp('pdf-raster-test');
    file = File('${directory.path}/pixels.rgba');
    await file.writeAsBytes(pixels);
    released = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'releaseRasterFile') {
        released.add(call.arguments as String);
        if (file.existsSync()) {
          await file.delete();
        }
        return null;
      }
      expect((call.arguments as Map)['rasterFile'], isTrue);
      return metadata();
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });

  Future<PdfRasterBuffer> render() async =>
      (await PdfRasterBuffer.render(
        'getTileImage',
        {'pageNumber': 1},
        () async => throw StateError('Must not fetch a second byte buffer'),
      ))!;

  test(
    'file import preserves RGBA after its transport file is released',
    () async {
      final raster = await render();
      final buffer = await raster.importBuffer(pixels.length);
      await raster.dispose();
      expect(file.existsSync(), isFalse);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: 2,
        height: 1,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final image = (await codec.getNextFrame()).image;
      final actual = await image.toByteData();
      expect(actual!.buffer.asUint8List(), pixels);
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      await raster.dispose();
      expect(released, ['owned-token']);
    },
  );

  for (final missing in [false, true]) {
    test(
      '${missing ? 'missing' : 'truncated'} file releases on import failure',
      () async {
        final raster = await render();
        if (missing) {
          await file.delete();
        } else {
          await file.writeAsBytes([0]);
        }
        await expectLater(
          raster.importBuffer(pixels.length),
          missing ? throwsException : throwsStateError,
        );
        await raster.dispose();
        expect(released, ['owned-token']);
      },
    );
  }

  for (final disposed in [false, true]) {
    test(
      'late file reply releases after ${disposed ? 'viewer disposal' : 'departure'}',
      () async {
        final queue = PdfRasterQueue();
        final native = Completer<PdfRasterBuffer?>();
        bool current = true;
        final releasedFile = Completer<void>();
        final result = queue.renderResource<PdfRasterBuffer>(
          () => native.future,
          () => current,
          onDiscard: (buffer) {
            unawaited(buffer.dispose().then((_) => releasedFile.complete()));
          },
        );
        if (disposed) {
          queue.dispose();
        } else {
          current = false;
        }
        native.complete(await render());
        expect(await result, isNull);
        await releasedFile.future;
        expect(released, ['owned-token']);
        expect(file.existsSync(), isFalse);
        queue.dispose();
      },
    );
  }

  test('older Android plugin byte replies still import', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => pixels);
    final raster = await render();
    final buffer = await raster.importBuffer(pixels.length);
    expect(buffer.length, pixels.length);
    buffer.dispose();
    await raster.dispose();
  });

  test(
    'other platforms preserve their registered platform implementation',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => fail('Android channel called'),
      );
      final raster =
          (await PdfRasterBuffer.render(
            'getTileImage',
            {},
            () async => pixels,
          ))!;
      final buffer = await raster.importBuffer(pixels.length);
      expect(buffer.length, pixels.length);
      buffer.dispose();
      expect(released, isEmpty);
    },
  );
}
