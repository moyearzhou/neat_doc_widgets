import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';
import 'package:syncfusion_pdfviewer_platform_interface/src/method_channel_pdfviewer.dart';

class _ListenerTrackingBinding extends AutomatedTestWidgetsFlutterBinding {
  final Set<VoidCallback> semanticsListeners = <VoidCallback>{};

  @override
  void addSemanticsEnabledListener(VoidCallback listener) {
    semanticsListeners.add(listener);
    super.addSemanticsEnabledListener(listener);
  }

  @override
  void removeSemanticsEnabledListener(VoidCallback listener) {
    semanticsListeners.remove(listener);
    super.removeSemanticsEnabledListener(listener);
  }
}

void main() {
  final binding = _ListenerTrackingBinding();

  testWidgets('closing and reopening a viewer releases semantics subscriptions',
      (tester) async {
    PdfViewerPlatform.instance = MethodChannelPdfViewer();
    const channel = MethodChannel('syncfusion_flutter_pdfviewer');
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'loadPdfFromFile':
          return '1';
        case 'getPagesWidth':
          return <double>[600];
        case 'getPagesHeight':
          return <double>[900];
        case 'getPage':
          final args = call.arguments as Map;
          return Uint8List((args['width'] as int) * (args['height'] as int) * 4);
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final document = PdfDocument()..pages.add();
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final baseline = Set<VoidCallback>.of(binding.semanticsListeners);
    for (int round = 0; round < 3; round++) {
      final controller = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
          home: SfPdfViewer.memory(bytes,
              controller: controller, canShowPageLoadingIndicator: false)));
      for (int i = 0; i < 60 && controller.pageCount == 0; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(controller.pageCount, 1);
      expect(binding.semanticsListeners.length, greaterThan(baseline.length));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 1));
      // The global binding must not keep a closed viewer, its document or
      // host callbacks reachable after the route has been removed.
      expect(binding.semanticsListeners, unorderedEquals(baseline),
          reason: 'Viewer $round retained a global semantics listener');
      controller.dispose();
    }
  });
}
