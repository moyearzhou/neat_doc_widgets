import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Routes native trackpad pan/zoom without claiming mouse, touch or pen input.
/// Place above annotation overlays so their drag recognizers cannot turn a
/// two-finger navigation gesture into an annotation edit.
class PdfTrackpadGestureRegion extends StatelessWidget {
  /// Creates a region sharing the viewer's native trackpad handler.
  const PdfTrackpadGestureRegion({
    required this.onEvent,
    required this.child,
    super.key,
  });

  /// Receives one arena-owned pan/zoom sequence and pointer interruptions.
  /// Down/scroll signals only cancel momentum; their gestures remain unclaimed.
  final ValueChanged<PointerEvent> onEvent;

  /// Viewer and optional annotation overlays.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The editor may wrap the viewer and its sibling annotation overlays.
    // Only that outer owner participates; nested recognizers would win first.
    if (context.dependOnInheritedWidgetOfExactType<_TrackpadOwner>() != null) {
      return child;
    }
    return _TrackpadOwner(
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          _TrackpadRecognizer:
              GestureRecognizerFactoryWithHandlers<_TrackpadRecognizer>(
                _TrackpadRecognizer.new,
                (recognizer) => recognizer.onEvent = onEvent,
              ),
        },
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollInertiaCancelEvent ||
                event is PointerScrollEvent) {
              onEvent(event);
            }
          },
          onPointerDown: onEvent,
          child: child,
        ),
      ),
    );
  }
}

class _TrackpadOwner extends InheritedWidget {
  const _TrackpadOwner({required super.child});

  @override
  bool updateShouldNotify(_TrackpadOwner oldWidget) => false;
}

class _TrackpadRecognizer extends OneSequenceGestureRecognizer {
  ValueChanged<PointerEvent>? onEvent;
  PointerPanZoomStartEvent? _start;
  bool _accepted = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) => false;

  @override
  void addAllowedPointer(PointerDownEvent event) {}

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (_start != null) {
      return;
    }
    _start = event;
    startTrackingPointer(event.pointer, event.transform);
    // Claim before overlay drag recognizers cross their slop threshold.
    resolve(GestureDisposition.accepted);
  }

  @override
  void acceptGesture(int pointer) {
    if (_start?.pointer != pointer || _accepted) {
      return;
    }
    _accepted = true;
    onEvent?.call(_start!);
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    _start = null;
    _accepted = false;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (_start?.pointer != event.pointer) {
      return;
    }
    if (_accepted &&
        (event is PointerPanZoomUpdateEvent ||
            event is PointerPanZoomEndEvent)) {
      onEvent?.call(event);
    }
    if (event is PointerPanZoomEndEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _start = null;
    _accepted = false;
  }

  @override
  String get debugDescription => 'PDF trackpad navigation';
}
