import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdfviewer/src/common/pdfviewer_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('syncfusion_flutter_pdfviewer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test(
    'close waits for in-flight initialization and shares one native release',
    () async {
      final loading = Completer<void>(), allowLoad = Completer<void>();
      var nativeCloses = 0;
      String? tempPath;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'loadPdfFromFile') {
          tempPath = (call.arguments as Map)['path'] as String?;
          loading.complete();
          await allowLoad.future;
          return '1';
        }
      if (call.method == 'closeDocument') {
        nativeCloses++;
      }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final plugin = PdfViewerPlugin();
      final initialized = plugin.initializePdfRenderer(
        Uint8List.fromList('%PDF-fixture'.codeUnits),
        null,
      );
      await loading.future;
      var released = false;
      final first = plugin.closeDocument().then((_) {
        released = true;
      });
      final duplicate = plugin.closeDocument();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(released, false);
      expect(nativeCloses, 0);
      allowLoad.complete();
      await initialized;
      await first;
      await duplicate;
      expect(nativeCloses, 1);
      expect(plugin.documentID, '');
    if (tempPath != null) {
      expect(File(tempPath!).existsSync(), false);
    }
      await plugin.closeDocument();
      expect(nativeCloses, 1);
    },
  );
}
