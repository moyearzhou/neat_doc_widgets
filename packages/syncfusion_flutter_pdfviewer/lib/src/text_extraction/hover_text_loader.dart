import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui';

/// Only line rectangles cross the worker boundary; hover needs no glyphs/text.
class HoverTextPage {
  HoverTextPage(this.geometry);

  /// Page height followed by groups of left, top, right, bottom coordinates.
  final Float64List geometry;

  bool contains(Offset position, double displayedHeight) {
    if (geometry.isEmpty || displayedHeight <= 0) {
      return false;
    }
    final Offset point = position * (geometry.first / displayedHeight);
    for (int i = 1; i + 3 < geometry.length; i += 4) {
      if (point.dx >= geometry[i] &&
          point.dy >= geometry[i + 1] &&
          point.dx < geometry[i + 2] &&
          point.dy < geometry[i + 3]) {
        return true;
      }
    }
    return false;
  }
}

/// One hover target per viewer. Short visits never start extraction, and an
/// obsolete running result cannot change the cursor or repopulate the cache.
class HoverTextLoader {
  HoverTextLoader({
    required this.extract,
    this.delay = const Duration(milliseconds: 180),
    this.maxCachedPages = 8,
    this.maxCachedRectangles = 8192,
  });

  final Future<Float64List?> Function(int page, bool Function() isCurrent)
  extract;
  final Duration delay;
  final int maxCachedPages;
  final int maxCachedRectangles;
  final LinkedHashMap<int, HoverTextPage> _cache =
      LinkedHashMap<int, HoverTextPage>();
  Timer? _timer;
  int? _target;
  int? _failedPage;
  void Function()? _onReady;
  int _generation = 0;
  bool _running = false;
  bool _disposed = false;
  bool _settling = false;

  bool get isSettling => _settling;

  HoverTextPage? hover(int page, void Function() onReady) {
    if (_disposed) {
      return null;
    }
    if (_target != page) {
      _generation++;
      _target = page;
      _failedPage = null;
      if (!_settling) {
        _timer?.cancel();
        _timer = null;
      }
    }
    _onReady = onReady;
    final HoverTextPage? cached = _cache.remove(page);
    if (cached != null) {
      _cache[page] = cached;
    }
    _schedule();
    return _settling ? null : cached;
  }

  void leave(int page) {
    if (_target == page) {
      _generation++;
      _target = null;
      _onReady = null;
      if (!_settling) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  /// Offset/zoom changes invalidate pending hover work, even within one page.
  /// Keep the last pointer so a stationary mouse recovers after scrolling ends.
  void viewportChanged() {
    if (_disposed) {
      return;
    }
    _generation++;
    _settling = true;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      _settling = false;
      _onReady?.call();
      _schedule();
    });
  }

  void _schedule() {
    if (_disposed ||
        _settling ||
        _running ||
        _timer != null ||
        _target == null ||
        _cache.containsKey(_target) ||
        _failedPage == _target) {
      return;
    }
    _timer = Timer(delay, _pump);
  }

  Future<void> _pump() async {
    _timer = null;
    final int? page = _target;
    if (_disposed || _settling || _running || page == null) {
      return;
    }
    final int generation = _generation;
    bool isCurrent() => !_disposed && generation == _generation;
    _running = true;
    try {
      Float64List? geometry;
      try {
        geometry = await extract(page, isCurrent);
      } catch (_) {
        // A malformed page must not break pointer handling or retry forever.
      }
      if (!isCurrent()) {
        return;
      }
      if (geometry == null) {
        _failedPage = page;
      } else {
        _cache[page] = HoverTextPage(geometry);
        int rectangles = _cache.values.fold<int>(
          0,
          (int total, HoverTextPage entry) =>
              total + (entry.geometry.length - 1) ~/ 4,
        );
        while (_cache.length > 1 &&
            (_cache.length > maxCachedPages ||
                rectangles > maxCachedRectangles)) {
          final HoverTextPage evicted = _cache.remove(_cache.keys.first)!;
          rectangles -= (evicted.geometry.length - 1) ~/ 4;
        }
      }
      _onReady?.call();
    } finally {
      _running = false;
      _schedule();
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _cache.clear();
    _onReady = null;
    _target = null;
  }
}
