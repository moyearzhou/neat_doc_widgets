import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_native_render_bridge.dart';

void main() {
  test('native buffer releases exactly once on duplicate cleanup', () {
    int releases = 0;
    final buffer = PdfNativePixelBuffer(Uint8List(4), () => releases++);
    buffer.dispose();
    buffer.dispose();
    expect(releases, 1);
    expect(() => buffer.pixels, throwsStateError);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = PdfNativeRenderBridge();
  const channel = MethodChannel('syncfusion_flutter_pdfviewer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getPage' ? Uint8List(4) : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'OHOS sends viewport priority independently of RGBA pixels',
    (tester) async {
      await bridge.getPage(2, 1, 1, 'reader', visible: false);
      await bridge.getPage(2, 1, 1, 'reader', visible: true);
      expect(calls.map((call) => call.method), ['getPage', 'getPage']);
      expect((calls[0].arguments as Map)['renderPriority'], 1);
      expect((calls[1].arguments as Map)['renderPriority'], 0);
      expect((calls[1].arguments as Map)['documentID'], 'reader');
    },
    variant: const TargetPlatformVariant({TargetPlatform.ohos}),
  );

  testWidgets(
    'OHOS detail forwards region and prewarm priority',
    (tester) async {
      await bridge.getTileImage(2, 3, 4, 5, 6, 7, 'reader', visible: false);
      await bridge.getTileImage(2, 3, 4, 5, 6, 7, 'reader', visible: true);
      expect(calls.map((call) => call.method), [
        'getTileImage',
        'getTileImage',
      ]);
      expect(calls[0].arguments, {
        'pageNumber': 2,
        'scale': 3.0,
        'x': 4.0,
        'y': 5.0,
        'width': 6.0,
        'height': 7.0,
        'documentID': 'reader',
        'renderPriority': 1,
      });
      expect((calls[1].arguments as Map)['renderPriority'], 0);
    },
    variant: const TargetPlatformVariant({TargetPlatform.ohos}),
  );

  testWidgets(
    'older native binary falls back for detail pixels',
    (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getTileBuffer') {
          throw MissingPluginException();
        }
        return Uint8List.fromList([1, 2, 3, 4]);
      });
      final buffer = await bridge.getDetailBuffer(
        2,
        3,
        4,
        5,
        1,
        1,
        'reader',
        visible: true,
      );
      expect(calls.map((call) => call.method), [
        'getTileBuffer',
        'getTileImage',
      ]);
      expect(buffer!.pixels, [1, 2, 3, 4]);
      buffer.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.ohos}),
  );

  testWidgets(
    'stale native detail does not allocate pixels',
    (tester) async {
      final buffer = await bridge.getDetailBuffer(
        2,
        3,
        4,
        5,
        1,
        1,
        'reader',
        visible: false,
      );
      expect(buffer, isNull);
      expect(calls.single.method, 'getTileBuffer');
      expect((calls.single.arguments as Map)['renderPriority'], 1);
    },
    variant: const TargetPlatformVariant({TargetPlatform.ohos}),
  );

  testWidgets(
    'OHOS forwards promotion, invalidation and viewport reentry',
    (tester) async {
      await bridge.updateState('reader', 2, active: true, visible: true);
      await bridge.updateState(
        'reader',
        2,
        active: false,
        visible: false,
        invalidate: true,
      );
      await bridge.updateState('reader', 2, active: true, visible: false);
      expect(
        calls.map((call) => call.method),
        List.filled(3, 'updateRenderState'),
      );
      expect((calls[0].arguments as Map)['visible'], isTrue);
      expect((calls[1].arguments as Map)['active'], isFalse);
      expect((calls[1].arguments as Map)['invalidate'], isTrue);
      expect((calls[2].arguments as Map)['active'], isTrue);
    },
    variant: const TargetPlatformVariant({TargetPlatform.ohos}),
  );

  testWidgets(
    'old native binaries continue rendering during hot reload',
    (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'updateRenderState') {
          throw MissingPluginException();
        }
        return Uint8List(4);
      });
      await bridge.updateState('reader', 1, active: false, visible: false);
      expect(
        await bridge.getPage(1, 1, 1, 'reader', visible: true),
        hasLength(4),
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.ohos}),
  );

  testWidgets(
    'other platforms retain the existing platform render protocol',
    (tester) async {
      await bridge.updateState('reader', 1, active: false, visible: false);
      await bridge.getPage(1, 1, 1, 'reader', visible: true);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'getPage');
      expect(
        (calls.single.arguments as Map).containsKey('renderPriority'),
        isFalse,
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
