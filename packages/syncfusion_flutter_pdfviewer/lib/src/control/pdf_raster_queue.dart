import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// Bounds native work across pages, including requests whose consumers left
/// the viewport. A native call cannot release its slot before actually ending.
class PdfRasterQueue {
  PdfRasterQueue({this.maxConcurrent = 2});

  final int maxConcurrent;
  final Queue<_RasterRequest<dynamic>> _pending =
      Queue<_RasterRequest<dynamic>>();
  int _running = 0;
  int _runningPrefetch = 0;
  bool _disposed = false;

  Future<Uint8List?> render(
    Future<Uint8List?> Function() operation,
    bool Function() isCurrent, {
    bool Function()? isVisible,
  }) => renderResource<Uint8List>(operation, isCurrent, isVisible: isVisible);

  /// Native raster resources need deterministic disposal when a request becomes
  /// stale after execution, including while the viewer is being disposed.
  Future<T?> renderResource<T>(
    Future<T?> Function() operation,
    bool Function() isCurrent, {
    bool Function()? isVisible,
    void Function(T)? onDiscard,
  }) {
    if (_disposed || !isCurrent()) {
      return Future<T?>.value();
    }
    final request = _RasterRequest<T>(
      operation,
      isCurrent,
      isVisible ?? () => true,
      onDiscard,
    );
    _pending.add(request);
    discardStale();
    _drain();
    return request.result.future;
  }

  /// A queued neighbor may become visible without submitting another request.
  void refreshPriorities() => scheduleMicrotask(_drain);

  void discardStale() {
    _pending.removeWhere((_RasterRequest<dynamic> request) {
      if (!_disposed && request.isCurrent()) {
        return false;
      }
      request.result.complete(null);
      return true;
    });
  }

  void _drain() {
    discardStale();
    while (!_disposed && _running < maxConcurrent && _pending.isNotEmpty) {
      final visible = _pending.where((request) => request.isVisible());
      // Reserve capacity for incoming visible pages. Speculative work may use
      // only one slot, and queued requests are reprioritized at dispatch time.
      if (visible.isEmpty && _runningPrefetch != 0) {
        return;
      }
      final request = visible.isNotEmpty ? visible.first : _pending.first;
      _pending.remove(request);
      final prefetch = !request.isVisible();
      _running++;
      if (prefetch) {
        _runningPrefetch++;
      }
      unawaited(_run(request, prefetch));
    }
  }

  Future<void> _run(_RasterRequest<dynamic> request, bool prefetch) async {
    try {
      final pixels = await request.operation();
      if (!_disposed && request.isCurrent()) {
        request.result.complete(pixels);
      } else {
        if (pixels != null) {
          request.discard(pixels);
        }
        request.result.complete(null);
      }
    } catch (error, stack) {
      request.result.completeError(error, stack);
    } finally {
      _running--;
      if (prefetch) {
        _runningPrefetch--;
      }
      _drain();
    }
  }

  void dispose() {
    _disposed = true;
    discardStale();
  }
}

class _RasterRequest<T> {
  _RasterRequest(
    this.operation,
    this.isCurrent,
    this.isVisible,
    this.onDiscard,
  );

  final Future<T?> Function() operation;
  final bool Function() isCurrent;
  final bool Function() isVisible;
  final void Function(T)? onDiscard;
  final Completer<T?> result = Completer<T?>();

  // The queue stores heterogeneous requests as dynamic. Invoke the callback
  // inside its typed owner: reading a Function(T) through dynamic otherwise
  // attempts an invalid Function(dynamic) cast and leaks stale resources.
  void discard(T value) => onDiscard?.call(value);
}
