import 'dart:isolate';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'cancellable_search_task.dart';

/// One cancellable full-document extraction, owned by a search lifecycle.
class TextExtractionEngine {
  TextExtractionEngine(this._bytes, [this._password]);
  final Uint8List _bytes;
  final String? _password;
  final CancellableSearchTask _task = CancellableSearchTask();
  bool _disposed = false;

  Future<Map<int, String>> extractText() async {
    if (_disposed) {
      return <int, String>{};
    }
    final result = <int, String>{};
    try {
      await _task.run(_extractText, <Object?>[_bytes, _password], (message) {
        if (!_disposed) {
          result.addAll((message! as Map).cast<int, String>());
        }
      });
      return _disposed ? <int, String>{} : result;
    } catch (_) {
      return <int, String>{};
    }
  }

  Future<void> dispose() {
    _disposed = true;
    return _task.cancel();
  }
}

void _extractText(List<Object?> arguments) {
  final reply = arguments[0]! as SendPort;
  final payload = arguments[1]! as List;
  // Only source bytes cross isolates; the viewer document can contain cached
  // resources, forms, selection geometry and other large mutable graphs.
  final document = PdfDocument(
    inputBytes: payload[0] as Uint8List,
    password: payload[1] as String?,
  );
  try {
    final extractor = PdfTextExtractor(document);
    for (int start = 0; start < document.pages.count; start += 30) {
      final result = <int, String>{};
      final end = (start + 30).clamp(0, document.pages.count);
      for (int page = start; page < end; page++) {
        result[page] =
            extractor
                .extractText(startPageIndex: page)
                .replaceAll(RegExp(r'\r?\n'), '')
                .toLowerCase();
      }
      reply.send(result);
    }
  } finally {
    document.dispose();
  }
}
