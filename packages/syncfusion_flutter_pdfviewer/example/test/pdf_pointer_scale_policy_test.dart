import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/common/pdfviewer_helper.dart';

void main() {
  test('OHOS uses pointer-aware scaling without changing mobile platforms', () {
    expect(usesPointerAwarePdfScaling(isDesktop: false, isOhos: true), isTrue);
    expect(usesPointerAwarePdfScaling(isDesktop: true, isOhos: false), isTrue);
    expect(
      usesPointerAwarePdfScaling(isDesktop: false, isOhos: false),
      isFalse,
    );
  });

  test('OHOS mouse wheel cannot scale while touch scaling stays enabled', () {
    expect(
      isPdfPointerScaleEnabled(
        isMobileWebView: false,
        pointerScaleEnabled: false,
        usesPointerAwareScaling: true,
      ),
      isFalse,
      reason: 'An idle OHOS PDF surface must reserve mouse wheel for scroll',
    );
    expect(
      isPdfPointerScaleEnabled(
        isMobileWebView: false,
        pointerScaleEnabled: true,
        usesPointerAwareScaling: true,
      ),
      isTrue,
      reason: 'Touch interaction must still be able to pinch zoom',
    );
  });

  test('mobile and mobile web scaling behavior remains unchanged', () {
    expect(
      isPdfPointerScaleEnabled(
        isMobileWebView: false,
        pointerScaleEnabled: false,
        usesPointerAwareScaling: false,
      ),
      isTrue,
    );
    expect(
      isPdfPointerScaleEnabled(
        isMobileWebView: true,
        pointerScaleEnabled: false,
        usesPointerAwareScaling: true,
      ),
      isTrue,
    );
  });

  testWidgets('OHOS mouse wheel scroll does not change the zoom matrix', (
    WidgetTester tester,
  ) async {
    final TransformationController controller = TransformationController();
    Offset? receivedScrollDelta;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: Listener(
              onPointerSignal: (PointerSignalEvent event) {
                if (event is PointerScrollEvent) {
                  receivedScrollDelta = event.scrollDelta;
                }
              },
              child: InteractiveViewer(
                transformationController: controller,
                minScale: 1,
                maxScale: 4,
                scaleEnabled: isPdfPointerScaleEnabled(
                  isMobileWebView: false,
                  pointerScaleEnabled: false,
                  usesPointerAwareScaling: true,
                ),
                child: const SizedBox(width: 600, height: 600),
              ),
            ),
          ),
        ),
      ),
    );

    final Offset center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, -20),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();

    expect(receivedScrollDelta, const Offset(0, -20));
    expect(controller.value.getMaxScaleOnAxis(), 1);
  });

  testWidgets('OHOS touch pinch still changes the zoom matrix', (
    WidgetTester tester,
  ) async {
    final TransformationController controller = TransformationController();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: InteractiveViewer(
              transformationController: controller,
              minScale: 1,
              maxScale: 4,
              scaleEnabled: isPdfPointerScaleEnabled(
                isMobileWebView: false,
                pointerScaleEnabled: true,
                usesPointerAwareScaling: true,
              ),
              child: const SizedBox(width: 600, height: 600),
            ),
          ),
        ),
      ),
    );

    final Offset center = tester.getCenter(find.byType(InteractiveViewer));
    final TestGesture firstFinger = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 1,
    );
    final TestGesture secondFinger = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await firstFinger.moveTo(center - const Offset(60, 0));
    await secondFinger.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await firstFinger.up();
    await secondFinger.up();

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
  });
}
