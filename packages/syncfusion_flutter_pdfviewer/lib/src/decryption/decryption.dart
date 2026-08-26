import 'dart:isolate';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Decrypts an encrypted PDF document.
class DecryptionEngine {
  DecryptionEngine();

  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  late final StreamQueue<dynamic> _receiveQueue = StreamQueue<dynamic>(
    _receivePort,
  );

  Future<Uint8List?> decrypt(Uint8List pdfBytes, String? password) async {
    try {
      _isolate = await Isolate.spawn(_decryption, _receivePort.sendPort);
      _sendPort = await _receiveQueue.next;
      final Map<String, dynamic> document = <String, dynamic>{
        'pdfBytes': pdfBytes,
        'password': password,
      };
      _sendPort!.send(document);

      final dynamic message = await _receiveQueue.next;
      if (message is Uint8List) {
        _isolate?.kill();
        return message;
      } else if (message is Map && message['error'] != null) {
        throw Exception(message['error'] as String);
      } else {
        throw Exception('Unexpected response from decrypt isolate: $message');
      }
    } catch (e) {
      return null;
    }
  }

  /// Disposes the resources used by the decryption engine.
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receiveQueue.cancel(immediate: true);
    _receivePort.close();
  }
}

/// Decrypts an encrypted PDF document.
void _decryption(SendPort sendPort) {
  final ReceivePort receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((dynamic message) {
    if (message is Map) {
      final Uint8List bytes = message['pdfBytes'] as Uint8List;
      final String? password = message['password'] as String?;
      final PdfDocument document = PdfDocument(
        inputBytes: bytes,
        password: password,
      );
      document.security.userPassword = '';
      document.security.ownerPassword = '';
      final Uint8List decryptedBytes = document.saveAsBytesSync();
      document.dispose();
      sendPort.send(decryptedBytes);
    }
  });
}
