import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/control/pdf_native_render_bridge.dart';

void main() {
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
