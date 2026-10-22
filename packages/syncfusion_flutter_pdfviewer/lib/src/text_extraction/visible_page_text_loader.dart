import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Loads accessibility text only for pages which remain visible after scrolling.
/// Queued work is replaced, rather than appended, when the viewport changes.
class VisiblePageTextLoader {
  VisiblePageTextLoader({
    required this.extract,
    required this.onLoaded,
    this.delay = const Duration(milliseconds: 180),
    this.maxCachedCharacters = 512 * 1024,
  });

  final Future<String?> Function(int pageIndex) extract;
  final void Function(int pageIndex, String text) onLoaded;
  final Duration delay;
  final int maxCachedCharacters;
  final LinkedHashMap<int, String> _cache = LinkedHashMap<int, String>();
  final Set<int> _failed = <int>{};
  List<int> _pages = <int>[];
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;
  int _characters = 0;

  String? textFor(int pageIndex) => _cache[pageIndex];

  void setPages(Iterable<int> pages) {
    if (_disposed) {
      return;
    }
    final List<int> next = pages.toSet().toList();
    if (next.length == _pages.length &&
        List<bool>.generate(
          next.length,
          (int i) => next[i] == _pages[i],
        ).every((bool equal) => equal)) {
      return;
    }
    _pages = next;
    _failed.removeWhere((int page) => !_pages.contains(page));
    _timer?.cancel();
    _timer = Timer(delay, _pump);
  }

  Future<void> _pump() async {
    _timer = null;
    if (_disposed || _running) {
      return;
    }
    _running = true;
    try {
      while (!_disposed) {
        // A newly entered page must also survive the debounce window while an
        // earlier native extraction is finishing.
        if (_timer?.isActive ?? false) {
          break;
        }
        final int? page = _pages.cast<int?>().firstWhere(
          (int? page) => !_cache.containsKey(page) && !_failed.contains(page),
          orElse: () => null,
        );
        if (page == null) {
          break;
        }
        String? text;
        try {
          text = await extract(page);
        } catch (_) {
          // A malformed page must not retry indefinitely or interrupt reading.
        }
        if (_disposed) {
          break;
        }
        if (text == null) {
          _failed.add(page);
          continue;
        }
        _cache[page] = text;
        _characters += text.length;
        // Preserve complete text for visible pages, even for an unusually long
        // page. Only offscreen entries are evicted; text is never truncated.
        for (final int key in _cache.keys.toList()) {
          if (_cache.length <= 16 && _characters <= maxCachedCharacters) {
            break;
          }
          if (!_pages.contains(key)) {
            _characters -= _cache.remove(key)!.length;
          }
        }
        if (_pages.contains(page)) {
          onLoaded(page, text);
        }
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cache.clear();
    _pages.clear();
  }
}

/// One lazy worker per accessible viewer. Sends source bytes once, never the
/// UI's parsed PdfDocument (which can contain a large graph of cached objects).
/// Ordinary reading does not create a worker or a second parsed document.
class PageTextWorker {
  PageTextWorker(Uint8List bytes, String? password) {
    _port.listen((dynamic message) {
      if (message is SendPort) {
        if (!_ready.isCompleted) {
          _ready.complete(message);
        }
      } else if (message is List &&
          message.length == 2 &&
          message.first is int) {
        _pending?.complete(message[1] as String?);
        _pending = null;
      } else {
        if (!_ready.isCompleted) {
          _ready.complete(null);
        }
        _pending?.complete(null);
        _pending = null;
      }
    });
    Isolate.spawn<List<Object?>>(
      _extractVisiblePageText,
      <Object?>[bytes, password, _port.sendPort],
      onError: _port.sendPort,
      onExit: _port.sendPort,
    ).then(
      (Isolate isolate) {
        if (_disposed) {
          isolate.kill(priority: Isolate.immediate);
        } else {
          _isolate = isolate;
        }
      },
      onError: (Object error) {
        if (!_ready.isCompleted) {
          _ready.complete(null);
        }
      },
    );
  }

  final ReceivePort _port = ReceivePort();
  final Completer<SendPort?> _ready = Completer<SendPort?>();
  Completer<String?>? _pending;
  Isolate? _isolate;
  bool _disposed = false;

  Future<String?> extract(int pageIndex) async {
    final SendPort? port = await _ready.future;
    if (_disposed || port == null) {
      return null;
    }
    assert(_pending == null, 'Page extraction must be serialized');
    final Completer<String?> pending = Completer<String?>();
    _pending = pending;
    port.send(pageIndex);
    return pending.future;
  }

  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _port.close();
    if (!_ready.isCompleted) {
      _ready.complete(null);
    }
    _pending?.complete(null);
    _pending = null;
  }
}

void _extractVisiblePageText(List<Object?> arguments) {
  final SendPort reply = arguments[2]! as SendPort;
  try {
    final PdfDocument document = PdfDocument(
      inputBytes: arguments[0]! as Uint8List,
      password: arguments[1] as String?,
    );
    final PdfTextExtractor extractor = PdfTextExtractor(document);
    final ReceivePort requests = ReceivePort();
    reply.send(requests.sendPort);
    requests.listen((dynamic page) {
      if (page is! int) {
        return;
      }
      try {
        reply.send(<Object?>[
          page,
          extractor.extractText(startPageIndex: page),
        ]);
      } catch (_) {
        reply.send(<Object?>[page, null]);
      }
    });
  } catch (_) {
    reply.send(null);
  }
}
